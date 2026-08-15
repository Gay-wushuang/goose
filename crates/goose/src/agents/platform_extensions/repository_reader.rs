use crate::agents::extension::PlatformExtensionContext;
use crate::agents::mcp_client::{Error, McpClientTrait};
use crate::agents::ToolCallContext;
use anyhow::Result;
use async_trait::async_trait;
use rmcp::model::{
    CallToolResult, ContentBlock, Implementation, InitializeResult, JsonObject, ListToolsResult,
    ServerCapabilities, Tool, ToolAnnotations,
};
use schemars::{schema_for, JsonSchema};
use serde::Deserialize;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;
use tokio_util::sync::CancellationToken;

pub static EXTENSION_NAME: &str = "repository_reader";
const MAX_READ_BYTES: usize = 256 * 1024;
const MAX_GIT_OUTPUT_BYTES: usize = 512 * 1024;

#[derive(Debug, Deserialize, JsonSchema)]
struct ReadParams {
    /// Repository-relative or absolute file path. It must remain inside the session repository.
    path: String,
    /// First one-based line to return.
    #[serde(default)]
    start_line: Option<usize>,
    /// Last one-based line to return (inclusive).
    #[serde(default)]
    end_line: Option<usize>,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct DiffParams {
    /// Optional repository-relative paths used to limit the diff.
    #[serde(default)]
    paths: Vec<String>,
    /// Return staged changes instead of unstaged changes.
    #[serde(default)]
    staged: bool,
}

pub struct RepositoryReaderClient {
    info: InitializeResult,
}

impl RepositoryReaderClient {
    pub fn new(_context: PlatformExtensionContext) -> Result<Self> {
        let info = InitializeResult::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(
                Implementation::new(EXTENSION_NAME, "1.0.0").with_title("Repository Reader"),
            )
            .with_instructions(
                "Read-only repository inspection. This extension exposes no write, edit, or arbitrary shell tool.",
            );
        Ok(Self { info })
    }

    fn schema<T: JsonSchema>() -> JsonObject {
        serde_json::to_value(schema_for!(T))
            .expect("schema serialization should succeed")
            .as_object()
            .expect("schema should serialize to an object")
            .clone()
    }

    fn tools() -> Vec<Tool> {
        let read_only = |title: &str| {
            ToolAnnotations::from_raw(
                Some(title.to_string()),
                Some(true),
                Some(false),
                Some(true),
                Some(false),
            )
        };
        vec![
            Tool::new(
                "read".to_string(),
                "Read a bounded UTF-8 text file or line range inside the repository.".to_string(),
                Self::schema::<ReadParams>(),
            )
            .annotate(read_only("Read Repository File")),
            Tool::new(
                "status".to_string(),
                "Run git status --short in the repository.".to_string(),
                Self::schema::<EmptyParams>(),
            )
            .annotate(read_only("Repository Status")),
            Tool::new(
                "diff".to_string(),
                "Read the current staged or unstaged git diff, optionally limited to paths."
                    .to_string(),
                Self::schema::<DiffParams>(),
            )
            .annotate(read_only("Repository Diff")),
        ]
    }

    fn parse<T: serde::de::DeserializeOwned>(arguments: Option<JsonObject>) -> Result<T, String> {
        serde_json::from_value(
            arguments
                .map(Value::Object)
                .unwrap_or(Value::Object(JsonObject::new())),
        )
        .map_err(|error| format!("Invalid arguments: {error}"))
    }

    fn repository(ctx: &ToolCallContext) -> Result<PathBuf, String> {
        let path = ctx
            .working_dir
            .as_deref()
            .ok_or_else(|| "Repository working directory is unavailable".to_string())?;
        path.canonicalize()
            .map_err(|error| format!("Cannot resolve repository: {error}"))
    }

    fn resolve_file(repository: &Path, requested: &str) -> Result<PathBuf, String> {
        let candidate = PathBuf::from(requested);
        let candidate = if candidate.is_absolute() {
            candidate
        } else {
            repository.join(candidate)
        };
        let resolved = candidate
            .canonicalize()
            .map_err(|error| format!("Cannot resolve file: {error}"))?;
        if !resolved.starts_with(repository) {
            return Err("Path is outside the repository".to_string());
        }
        if !resolved.is_file() {
            return Err("Path is not a file".to_string());
        }
        Ok(resolved)
    }

    fn read(ctx: &ToolCallContext, params: ReadParams) -> CallToolResult {
        let result = (|| -> Result<String, String> {
            let repository = Self::repository(ctx)?;
            let path = Self::resolve_file(&repository, &params.path)?;
            let bytes = std::fs::read(&path).map_err(|error| format!("Read failed: {error}"))?;
            if bytes.len() > MAX_READ_BYTES {
                return Err(format!(
                    "File is {} bytes; request a smaller source artifact or use bounded repository evidence (limit {} bytes)",
                    bytes.len(), MAX_READ_BYTES
                ));
            }
            let text =
                String::from_utf8(bytes).map_err(|_| "File is not UTF-8 text".to_string())?;
            let lines: Vec<&str> = text.lines().collect();
            let start = params.start_line.unwrap_or(1);
            let end = params.end_line.unwrap_or(lines.len());
            if start == 0 || end < start {
                return Err("Line range must be one-based and end_line >= start_line".to_string());
            }
            let selected = lines
                .iter()
                .enumerate()
                .filter(|(index, _)| {
                    let line = index + 1;
                    line >= start && line <= end
                })
                .map(|(index, line)| format!("{}: {}", index + 1, line))
                .collect::<Vec<_>>()
                .join("\n");
            Ok(selected)
        })();
        match result {
            Ok(text) => CallToolResult::success(vec![ContentBlock::text(text)]),
            Err(error) => CallToolResult::error(vec![ContentBlock::text(error)]),
        }
    }

    fn git(ctx: &ToolCallContext, args: &[String]) -> CallToolResult {
        let result = (|| -> Result<String, String> {
            let repository = Self::repository(ctx)?;
            let output = Command::new("git")
                .arg("-C")
                .arg(repository)
                .args(args)
                .output()
                .map_err(|error| format!("Failed to run git: {error}"))?;
            let mut bytes = output.stdout;
            bytes.extend_from_slice(&output.stderr);
            if bytes.len() > MAX_GIT_OUTPUT_BYTES {
                bytes.truncate(MAX_GIT_OUTPUT_BYTES);
                bytes.extend_from_slice(b"\n[output truncated]\n");
            }
            let text = String::from_utf8_lossy(&bytes).into_owned();
            if output.status.success() {
                Ok(text)
            } else {
                Err(format!("git exited with {}\n{text}", output.status))
            }
        })();
        match result {
            Ok(text) => CallToolResult::success(vec![ContentBlock::text(text)]),
            Err(error) => CallToolResult::error(vec![ContentBlock::text(error)]),
        }
    }
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
struct EmptyParams {}

#[async_trait]
impl McpClientTrait for RepositoryReaderClient {
    async fn list_tools(
        &self,
        _session_id: &str,
        _next_cursor: Option<String>,
        _cancellation_token: CancellationToken,
    ) -> Result<ListToolsResult, Error> {
        Ok(ListToolsResult {
            tools: Self::tools(),
            next_cursor: None,
            meta: None,
        })
    }

    async fn call_tool(
        &self,
        ctx: &ToolCallContext,
        name: &str,
        arguments: Option<JsonObject>,
        _cancel_token: CancellationToken,
    ) -> Result<CallToolResult, Error> {
        let result = match name {
            "read" => Self::parse::<ReadParams>(arguments).map(|params| Self::read(ctx, params)),
            "status" => Self::parse::<EmptyParams>(arguments)
                .map(|_| Self::git(ctx, &["status".to_string(), "--short".to_string()])),
            "diff" => Self::parse::<DiffParams>(arguments).map(|params| {
                let mut args = vec!["diff".to_string()];
                if params.staged {
                    args.push("--cached".to_string());
                }
                if !params.paths.is_empty() {
                    args.push("--".to_string());
                    args.extend(params.paths);
                }
                Self::git(ctx, &args)
            }),
            _ => Err(format!("Unknown read-only repository tool: {name}")),
        };
        Ok(match result {
            Ok(output) => output,
            Err(error) => CallToolResult::error(vec![ContentBlock::text(error)]),
        })
    }

    fn get_info(&self) -> Option<&InitializeResult> {
        Some(&self.info)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_only_read_only_tools() {
        let names = RepositoryReaderClient::tools()
            .into_iter()
            .map(|tool| tool.name.to_string())
            .collect::<Vec<_>>();
        assert_eq!(names, vec!["read", "status", "diff"]);
        assert!(!names
            .iter()
            .any(|name| name == "write" || name == "edit" || name == "shell"));
    }
}
