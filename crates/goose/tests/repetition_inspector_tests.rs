use goose::tool_monitor::{classify_tool_failure, FailureType};
use goose::tool_monitor::{ProgressDecision, ProgressWatchdog, RepetitionInspector};
use rmcp::model::{CallToolRequestParams, CallToolResult, ContentBlock};
use rmcp::object;

// This test targets RepetitionInspector::check_tool_call
// It verifies that:
// - consecutive identical tool calls are allowed up to max_repetitions times
// - the (max_repetitions + 1)th identical call is denied (returns false)
// - changing the parameters resets the repetition count and allows the call
#[test]
fn test_repetition_inspector_denies_after_exceeding_and_resets_on_param_change() {
    // Allow at most 2 consecutive identical calls
    let inspector = RepetitionInspector::new(Some(2));

    // First identical call → allowed
    let call_v1 = CallToolRequestParams::new("fetch_user").with_arguments(object!({"id": 123}));
    assert!(inspector.check_tool_call(call_v1.clone()));

    // Second identical call → still allowed (at limit)
    assert!(inspector.check_tool_call(call_v1.clone()));

    // Third identical call → should be denied (exceeds limit)
    assert!(!inspector.check_tool_call(call_v1.clone()));

    // Change parameters; this should reset the consecutive counter
    let call_v2 = CallToolRequestParams::new("fetch_user").with_arguments(object!({"id": 456}));

    assert!(inspector.check_tool_call(call_v2.clone()));

    // Another identical call with new params → allowed (second in a row for this variant)
    assert!(inspector.check_tool_call(call_v2.clone()));

    // One more identical call with new params → denied again
    assert!(!inspector.check_tool_call(call_v2));
}

#[tokio::test]
async fn test_repetition_inspector_trait_persists_state_between_inspections() {
    use goose::config::GooseMode;
    use goose::conversation::message::ToolRequest;
    use goose::tool_inspection::{InspectionAction, ToolInspector};

    let inspector = RepetitionInspector::new(Some(2));
    let call = CallToolRequestParams::new("edit").with_arguments(object!({
        "path": "SnakeGame.cs",
        "before": "same",
        "after": "same"
    }));

    for index in 0..2 {
        let request = ToolRequest {
            id: format!("call-{index}"),
            tool_call: Ok(call.clone()),
            metadata: None,
            tool_meta: None,
        };
        let results = inspector
            .inspect("session", &[request], &[], GooseMode::Auto)
            .await
            .unwrap();
        assert!(results.is_empty());
    }

    let request = ToolRequest {
        id: "call-3".to_string(),
        tool_call: Ok(call),
        metadata: None,
        tool_meta: None,
    };
    let results = inspector
        .inspect("session", &[request], &[], GooseMode::Auto)
        .await
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].action, InspectionAction::Deny);
    assert_eq!(results[0].finding_id.as_deref(), Some("REP-001"));
}

#[tokio::test]
async fn repeated_read_warns_without_denial() {
    use goose::config::GooseMode;
    use goose::conversation::message::ToolRequest;
    use goose::tool_inspection::{InspectionAction, ToolInspector};

    let inspector = RepetitionInspector::new(Some(2));
    let call = CallToolRequestParams::new("developer__read")
        .with_arguments(object!({ "path": "SnakeGame.cs" }));

    for index in 0..3 {
        let request = ToolRequest {
            id: format!("read-{index}"),
            tool_call: Ok(call.clone()),
            metadata: None,
            tool_meta: None,
        };
        let results = inspector
            .inspect("session", &[request], &[], GooseMode::Auto)
            .await
            .unwrap();
        if index < 2 {
            assert!(results.is_empty());
        } else {
            assert_eq!(results[0].action, InspectionAction::Allow);
            assert_eq!(results[0].finding_id.as_deref(), Some("REP-WARN"));
        }
    }
}

#[test]
fn no_progress_watchdog_warns_then_aborts() {
    let mut watchdog = ProgressWatchdog::default();
    assert_eq!(
        watchdog.observe(10, 20, Some(30), Some(30), true),
        ProgressDecision::Progress
    );
    assert_eq!(
        watchdog.observe(10, 20, Some(30), Some(30), true),
        ProgressDecision::Warning
    );
    assert_eq!(
        watchdog.observe(10, 20, Some(30), Some(30), true),
        ProgressDecision::Abort
    );
    let metrics = watchdog.metrics();
    assert_eq!(metrics.tool_calls, 3);
    assert_eq!(metrics.executed_tool_calls, 3);
    assert_eq!(metrics.productive_actions, 1);
    assert_eq!(metrics.failed_actions, 3);
    assert_eq!(metrics.blocked_actions, 0);
    assert_eq!(metrics.no_progress_actions, 2);
    assert_eq!(metrics.loop_breaks, 1);
    assert_eq!(metrics.execution_efficiency(), 1.0 / 3.0);
    assert_eq!(metrics.agent_efficiency(3), 1.0 / 3.0);
}

#[test]
fn blocked_runtime_actions_are_counted_as_agent_behavior() {
    let mut watchdog = ProgressWatchdog::default();
    watchdog.observe(10, 20, Some(30), Some(30), true);
    watchdog.record_blocked(false);
    watchdog.record_blocked(true);

    let metrics = watchdog.metrics();
    assert_eq!(metrics.executed_tool_calls, 1);
    assert_eq!(metrics.productive_actions, 1);
    assert_eq!(metrics.failed_actions, 1);
    assert_eq!(metrics.blocked_actions, 2);
    assert_eq!(metrics.no_progress_actions, 2);
    assert_eq!(metrics.loop_breaks, 1);
    assert_eq!(metrics.execution_efficiency(), 1.0);
    assert_eq!(metrics.agent_efficiency(3), 1.0 / 3.0);
}

#[test]
fn no_progress_watchdog_resets_on_state_or_result_change() {
    let mut watchdog = ProgressWatchdog::default();
    watchdog.observe(10, 20, Some(30), Some(30), true);
    assert_eq!(
        watchdog.observe(10, 20, Some(30), Some(31), true),
        ProgressDecision::Progress
    );
    assert_eq!(
        watchdog.observe(10, 21, Some(31), Some(31), false),
        ProgressDecision::Progress
    );
    assert_eq!(watchdog.metrics().recovery_count, 1);
}

fn error_result(message: &str) -> CallToolResult {
    CallToolResult::error(vec![ContentBlock::text(message)])
}

#[test]
fn deterministic_failure_classifier_recognizes_edit_failures() {
    let no_op =
        classify_tool_failure("developer__edit", &error_result("NO_OP_EDIT: no changes")).unwrap();
    assert_eq!(no_op.failure_type, FailureType::NoOpEdit);
    assert_eq!(no_op.required_next_action, Some("READ_BEFORE_RETRY"));

    let mismatch = classify_tool_failure(
        "edit",
        &error_result("No match found for the specified text."),
    )
    .unwrap();
    assert_eq!(mismatch.failure_type, FailureType::StateMismatch);

    let ambiguous = classify_tool_failure(
        "edit",
        &error_result("Found 3 matches. Please provide more context to identify a unique match:"),
    )
    .unwrap();
    assert_eq!(ambiguous.failure_type, FailureType::AmbiguousMatch);
}

#[test]
fn deterministic_failure_classifier_recognizes_runtime_failures() {
    let path = classify_tool_failure(
        "shell",
        &error_result("Get-Content: Cannot find path C:\\missing.txt"),
    )
    .unwrap();
    assert_eq!(path.failure_type, FailureType::PathError);

    let permission = classify_tool_failure("shell", &error_result("Access is denied")).unwrap();
    assert_eq!(permission.failure_type, FailureType::PermissionError);

    let timeout =
        classify_tool_failure("shell", &error_result("Command timed out after 30 seconds"))
            .unwrap();
    assert_eq!(timeout.failure_type, FailureType::Timeout);
}

#[test]
fn unknown_engine_or_compile_failure_stays_unclassified() {
    let diagnosis =
        classify_tool_failure("shell", &error_result("Godot: Node not found: PauseLabel")).unwrap();
    assert_eq!(diagnosis.failure_type, FailureType::Unclassified);
    assert_eq!(diagnosis.confidence, 0.0);
    assert!(!diagnosis.automatic_repair);
}
