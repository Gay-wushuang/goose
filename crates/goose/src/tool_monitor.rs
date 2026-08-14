use crate::config::GooseMode;
use crate::conversation::message::{Message, ToolRequest};
use crate::tool_inspection::{InspectionAction, InspectionResult, ToolInspector};
use anyhow::Result;
use async_trait::async_trait;
use rmcp::model::CallToolRequestParams;
use rmcp::model::CallToolResult;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum FailureType {
    NoOpEdit,
    StateMismatch,
    AmbiguousMatch,
    PathError,
    PermissionError,
    ProtocolError,
    Timeout,
    Unclassified,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct FailureDiagnosis {
    pub failure_type: FailureType,
    pub confidence: f32,
    pub allowed_actions: Vec<&'static str>,
    pub required_next_action: Option<&'static str>,
    pub automatic_repair: bool,
}

pub fn classify_tool_failure(tool_name: &str, result: &CallToolResult) -> Option<FailureDiagnosis> {
    if !result.is_error.unwrap_or(false) {
        return None;
    }

    let serialized = serde_json::to_string(result).unwrap_or_default();
    let lower = serialized.to_ascii_lowercase();
    let short_name = tool_name.rsplit("__").next().unwrap_or(tool_name);

    let diagnosis = if short_name == "edit" && serialized.contains("NO_OP_EDIT") {
        FailureDiagnosis {
            failure_type: FailureType::NoOpEdit,
            confidence: 1.0,
            allowed_actions: vec!["READ_TARGET", "GENERATE_NEW_CHANGE"],
            required_next_action: Some("READ_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else if short_name == "edit" && serialized.contains("No match found for the specified text") {
        FailureDiagnosis {
            failure_type: FailureType::StateMismatch,
            confidence: 1.0,
            allowed_actions: vec!["READ_TARGET", "REBUILD_PATCH"],
            required_next_action: Some("READ_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else if short_name == "edit" && serialized.contains("matches. Please provide more context") {
        FailureDiagnosis {
            failure_type: FailureType::AmbiguousMatch,
            confidence: 1.0,
            allowed_actions: vec!["READ_TARGET", "EXPAND_MATCH_CONTEXT"],
            required_next_action: Some("READ_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else if lower.contains("permission denied") || lower.contains("access is denied") {
        FailureDiagnosis {
            failure_type: FailureType::PermissionError,
            confidence: 1.0,
            allowed_actions: vec!["STOP", "REQUEST_AUTHORIZATION"],
            required_next_action: Some("STOP_AND_REPORT"),
            automatic_repair: false,
        }
    } else if lower.contains("no such file")
        || lower.contains("cannot find path")
        || lower.contains("file not found")
        || lower.contains("os error 2")
    {
        FailureDiagnosis {
            failure_type: FailureType::PathError,
            confidence: 1.0,
            allowed_actions: vec!["CHECK_DECLARED_PATH"],
            required_next_action: Some("CHECK_PATH_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else if lower.contains("timed_out\":true") || lower.contains("command timed out after") {
        FailureDiagnosis {
            failure_type: FailureType::Timeout,
            confidence: 1.0,
            allowed_actions: vec!["CHECK_PROCESS_STATE", "CHANGE_STRATEGY"],
            required_next_action: Some("OBSERVE_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else if lower.contains("invalid parameter") || lower.contains("missing required") {
        FailureDiagnosis {
            failure_type: FailureType::ProtocolError,
            confidence: 1.0,
            allowed_actions: vec!["CORRECT_TOOL_ARGUMENTS"],
            required_next_action: Some("CORRECT_ARGUMENTS_BEFORE_RETRY"),
            automatic_repair: false,
        }
    } else {
        FailureDiagnosis {
            failure_type: FailureType::Unclassified,
            confidence: 0.0,
            allowed_actions: vec!["DIAGNOSE", "ASK_USER", "ESCALATE_CODEX"],
            required_next_action: None,
            automatic_repair: false,
        }
    };

    Some(diagnosis)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgressDecision {
    Progress,
    Warning,
    Abort,
}

#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ProgressMetrics {
    /// Backward-compatible count of tool calls that reached execution.
    pub tool_calls: u64,
    pub executed_tool_calls: u64,
    pub productive_actions: u64,
    pub failed_actions: u64,
    pub blocked_actions: u64,
    pub no_progress_actions: u64,
    pub recovery_count: u64,
    pub loop_breaks: u64,
}

impl ProgressMetrics {
    pub fn execution_efficiency(&self) -> f64 {
        if self.executed_tool_calls == 0 {
            0.0
        } else {
            self.productive_actions as f64 / self.executed_tool_calls as f64
        }
    }

    pub fn agent_efficiency(&self, generated_tool_calls: u64) -> f64 {
        if generated_tool_calls == 0 {
            0.0
        } else {
            self.productive_actions as f64 / generated_tool_calls as f64
        }
    }

    pub fn progress_efficiency(&self) -> f64 {
        self.execution_efficiency()
    }
}

#[derive(Debug, Default)]
pub struct ProgressWatchdog {
    last_request_hash: Option<u64>,
    last_result_hash: Option<u64>,
    last_failed: bool,
    consecutive_no_progress: u32,
    metrics: ProgressMetrics,
}

impl ProgressWatchdog {
    pub fn observe(
        &mut self,
        request_hash: u64,
        result_hash: u64,
        state_before: Option<u64>,
        state_after: Option<u64>,
        failed: bool,
    ) -> ProgressDecision {
        self.metrics.tool_calls += 1;
        self.metrics.executed_tool_calls += 1;
        if failed {
            self.metrics.failed_actions += 1;
        }
        let state_changed = matches!((state_before, state_after), (Some(a), Some(b)) if a != b);
        let same_observation = self.last_request_hash == Some(request_hash)
            && self.last_result_hash == Some(result_hash)
            && !state_changed;

        if self.last_failed && !failed {
            self.metrics.recovery_count += 1;
        }

        let decision = if same_observation {
            self.consecutive_no_progress += 1;
            self.metrics.no_progress_actions += 1;
            if self.consecutive_no_progress >= 2 {
                self.metrics.loop_breaks += 1;
                ProgressDecision::Abort
            } else {
                ProgressDecision::Warning
            }
        } else {
            self.consecutive_no_progress = 0;
            self.metrics.productive_actions += 1;
            ProgressDecision::Progress
        };

        self.last_request_hash = Some(request_hash);
        self.last_result_hash = Some(result_hash);
        self.last_failed = failed;
        decision
    }

    /// Record a generated action that Runtime rejected before tool execution.
    /// A rejected recovery/repetition action is still agent behavior and must
    /// count as no progress even though the underlying tool never ran.
    pub fn record_blocked(&mut self, broke_loop: bool) {
        self.metrics.blocked_actions += 1;
        self.metrics.no_progress_actions += 1;
        if broke_loop {
            self.metrics.loop_breaks += 1;
        }
    }

    pub fn metrics(&self) -> ProgressMetrics {
        self.metrics.clone()
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }
}

// Helper struct for internal tracking
#[derive(Debug, Clone)]
struct InternalToolCall {
    name: String,
    parameters: Value,
}

impl InternalToolCall {
    fn matches(&self, other: &InternalToolCall) -> bool {
        self.name == other.name && self.parameters == other.parameters
    }

    fn from_tool_call(tool_call: &CallToolRequestParams) -> Self {
        let name = tool_call.name.to_string();
        let parameters = tool_call
            .arguments
            .as_ref()
            .map(|obj| Value::Object(obj.clone()))
            .unwrap_or(Value::Null);
        Self { name, parameters }
    }
}

#[derive(Debug)]
pub struct RepetitionInspector {
    max_repetitions: Option<u32>,
    state: Mutex<RepetitionState>,
}

fn is_fatal_repetition_tool(name: &str) -> bool {
    let short_name = name.rsplit("__").next().unwrap_or(name);
    matches!(short_name, "edit" | "write" | "shell")
}

#[derive(Debug, Default)]
struct RepetitionState {
    last_call: Option<InternalToolCall>,
    repeat_count: u32,
    call_counts: HashMap<String, u32>,
}

impl RepetitionInspector {
    pub fn new(max_repetitions: Option<u32>) -> Self {
        Self {
            max_repetitions,
            state: Mutex::new(RepetitionState::default()),
        }
    }

    pub fn check_tool_call(&self, tool_call: CallToolRequestParams) -> bool {
        let internal_call = InternalToolCall::from_tool_call(&tool_call);
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let total_calls = state
            .call_counts
            .entry(internal_call.name.clone())
            .or_insert(0);
        *total_calls += 1;

        if self.max_repetitions.is_none() {
            state.last_call = Some(internal_call);
            state.repeat_count = 1;
            return true;
        }

        if let Some(last) = &state.last_call {
            if last.matches(&internal_call) {
                state.repeat_count += 1;
                if state.repeat_count > self.max_repetitions.unwrap() {
                    return false;
                }
            } else {
                state.repeat_count = 1;
            }
        } else {
            state.repeat_count = 1;
        }

        state.last_call = Some(internal_call);
        true
    }

    pub fn reset(&self) {
        *self.state.lock().unwrap_or_else(|e| e.into_inner()) = RepetitionState::default();
    }
}

#[async_trait]
impl ToolInspector for RepetitionInspector {
    fn name(&self) -> &'static str {
        "repetition"
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    async fn inspect(
        &self,
        _session_id: &str,
        tool_requests: &[ToolRequest],
        _messages: &[Message],
        _goose_mode: GooseMode,
    ) -> Result<Vec<InspectionResult>> {
        let mut results = Vec::new();

        // Check repetition limits for each tool request
        for tool_request in tool_requests {
            if let Ok(tool_call) = &tool_request.tool_call {
                if !self.check_tool_call(tool_call.clone()) {
                    let fatal = is_fatal_repetition_tool(tool_call.name.as_ref());
                    results.push(InspectionResult {
                        tool_request_id: tool_request.id.clone(),
                        action: if fatal {
                            InspectionAction::Deny
                        } else {
                            InspectionAction::Allow
                        },
                        reason: format!(
                            "Tool '{}' has exceeded maximum repetitions{}",
                            tool_call.name,
                            if fatal {
                                " and was blocked"
                            } else {
                                "; warning only because this tool may be read-only or polling"
                            }
                        ),
                        confidence: 1.0,
                        inspector_name: "repetition".to_string(),
                        finding_id: Some(if fatal {
                            "REP-001".to_string()
                        } else {
                            "REP-WARN".to_string()
                        }),
                    });
                }
            }
        }

        Ok(results)
    }
}
