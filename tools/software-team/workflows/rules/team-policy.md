# Universal AI Software Team Policy

## Invariants
- One writer at a time per working tree. Planning and review are read-only.
- Inspect repository instructions and `git status` before work.
- Preserve unrelated user changes; never reset, clean, force-push, or rewrite history.
- Never commit, push, install dependencies, or perform destructive operations without explicit approval.
- The actual diff and command output are authoritative; agent summaries are not.
- A failed or omitted verification must be reported, never presented as success.
- Read and enforce the target repository's `AGENTS.md` and equivalent local instructions. If none exists, apply this policy as the minimum project rule set.
- Worker reports are untrusted structured claims. Only independently observed files, `git diff`, and command exit status may transition the workflow.
- A missing, malformed, literal `^`, relative, or nonexistent repository path is a hard input error. Ask for a corrected absolute path; never search unrelated directories or drives to guess it.

## Routing contract
- `REVIEW_ONLY`: explanation, design, audit, or review with no requested edit -> Codex architect/reviewer only.
- `SMALL`: clear, localized, low-risk work such as a focused single-file edit, simple script, documentation/extraction, mechanical transformation, or narrow test helper -> Gemma E4B Fast Worker. Escalate on ambiguity, coordinated multi-file work, or recovery.
- `LARGE`: multi-file implementation, state machines, architecture-sensitive changes, non-trivial debugging/refactoring, error recovery, new subsystems, or complex algorithms -> Gemma 4 26B A4B Primary Worker.
- Any public API/schema/dependency/destructive/broad-refactor task requires approval after Codex planning.
- If a local agent violates scope, stop it and return control to Codex.

## Serial gates
Baseline -> Architect/classify (`REVIEW_ONLY`, `SMALL`, or `LARGE`) -> approval when required -> one implementation agent -> independent diff/content/test gate -> Codex review -> bounded repair (maximum two loops) -> final verification -> report.

## State transitions
- `START -> BASELINE`: repository path resolves and status/instructions are captured.
- `BASELINE -> PLAN`: no unsafe repository condition is hidden.
- `PLAN -> WAITING_APPROVAL`: the plan requires approval; make no writes.
- `PLAN -> IMPLEMENT`: classification is `SMALL` or `LARGE`, scope is explicit, and approval is not required or has been granted.
- `PLAN -> REVIEW`: classification is `REVIEW_ONLY`.
- `IMPLEMENT -> PREFLIGHT`: implementation stopped and the coordinator has captured the actual repository state.
- `PREFLIGHT -> REVIEW`: every required deterministic validator passes.
- `PREFLIGHT -> PREFLIGHT_FIX`: a validator provides a bounded, localized, mechanically actionable failure and fewer than two preflight fixes have run.
- `PREFLIGHT_FIX -> PREFLIGHT`: rerun the complete affected validator set; never accept only the worker's claim.
- `PREFLIGHT -> REVIEW`: a failure is ambiguous, behavioral, architecture-sensitive, cross-cutting, or not safely auto-fixable; pass the evidence to Codex without speculative edits.
- `PREFLIGHT -> BLOCKED`: required validation cannot run, safety/scope cannot be established, or two preflight fixes failed to clear the deterministic gates.
- `IMPLEMENT -> FAST_VERIFY`: an E4B SMALL task returned a valid report and has deterministic acceptance commands.
- `FAST_VERIFY -> DONE`: only for SMALL work when the coordinator independently proves authorized scope, expected content, and every deterministic check passes. This is a mechanical acceptance, not a model self-approval.
- `FAST_VERIFY -> REPAIR`: a localized, bounded failure is repairable and the repair count is below two.
- `FAST_VERIFY -> REVIEW`: scope/risk expanded, evidence is ambiguous, or a semantic review is needed.
- `IMPLEMENT -> REVIEW`: a fresh independent diff proves requested changes exist, changed paths are authorized, and required verification was actually executed.
- `IMPLEMENT -> REPAIR`: reserved for a semantic repair directed by Codex; deterministic implementation failures go through PREFLIGHT first.
- `REVIEW -> DONE`: only `REVIEW_RESULT_V2.status == APPROVE` plus the coordinator's independent gate.
- `REVIEW -> REPAIR`: only `REVIEW_RESULT_V2.status == REPAIR` and repair count is below two.
- `REVIEW -> BLOCKED`: reviewer says `BLOCKED`, the failure requires new user authority/architecture, scope is violated, or two repairs have failed.
- Never transition based only on a worker's `PATCH_APPLIED` claim.

## Git authority
- `git status`, `git diff`, and non-mutating history inspection are mandatory evidence.
- Do not create/switch branches, stage, commit, push, merge, reset, clean, or rewrite history unless the user explicitly authorizes that Git action.
- If commit is authorized, commit only after `DONE`, show the exact staged diff, and never include unrelated changes.

## Structured protocols
- Architect: `TASK_PLAN_V1` JSON.
- E4B Fast Worker and lightweight preflight fixer: `IMPLEMENTATION_REPORT_V1` JSON.
- Coordinator to A4B Primary Worker: `A4B_IMPLEMENTATION_HANDOFF_V1` JSON.
- A4B Primary Worker: `A4B_EXECUTION_REPORT_V1` JSON.
- Codex reviewer: `REVIEW_RESULT_V2` JSON.
- Coordinator to A4B semantic repair: `A4B_REPAIR_HANDOFF_V1` JSON.
- Malformed/missing protocol is not success. Request one report-only correction without code changes and without consuming either repair budget. If it remains invalid, continue only when independent repository evidence establishes scope and validation safely; otherwise block.

## A4B handoff boundary
- Never forward raw architect prose, the full chat history, or a raw reviewer report to A4B.
- Compile the approved plan into `A4B_IMPLEMENTATION_HANDOFF_V1`, preserving its `plan_id` and `AC-*` IDs, and validate it against the versioned schema before delegation.
- The handoff must contain observed repository facts, exact authorized files, explicit forbidden changes, ordered `READ`/`IMPLEMENT`/`VERIFY` actions, concrete evidence requirements, recovery policy, and stop conditions.
- Treat `A4B_EXECUTION_REPORT_V1` only as an untrusted claim. Git diff, file contents, and deterministic command results are authoritative.
- Compile a `REPAIR` verdict into `A4B_REPAIR_HANDOFF_V1`; include only actionable `F-*` findings, exact files, behavior to preserve, verification, and a required first `READ` action.
- Validate all four A4B/Review contracts against their schemas in `workflows/contracts/` before changing state.

## Preflight validation and lightweight repair
- Validators are deterministic commands selected from repository and stack rules: diff/whitespace checks, conflict-marker scans, parsers, compilers, linters, tests, engine imports, resource resolution, and structured-protocol schema validation.
- Run validators before Codex semantic review. Validators do not consume model tokens except when a lightweight fix is actually delegated.
- `PREFLIGHT_FIX` is a separate budget from semantic repair: maximum two attempts per workflow.
- E4B may perform a preflight fix only when the diagnostic identifies an explicit localized defect, the authorized files are exact, the change preserves design/behavior, and the validator can conclusively recheck it.
- Examples that may qualify: formatting/parse defects, an exact misspelled symbol or resource path, a missing import proven by the compiler, or a required manifest field with an unambiguous value already established by repository evidence.
- Never auto-fix dependency/SDK versions, public APIs, schemas, gameplay/business logic, security behavior, architecture, broad resource graphs, or ambiguous compiler/test failures. Send these to Codex review.
- A failed E4B tool call, scope expansion, or non-local edit ends lightweight repair and escalates; it never silently consumes semantic repair.
- Codex semantic `REPAIR` has its own maximum of two implementation attempts, normally routed to the Primary Worker (26B).

## Runtime progress guard
- A write/edit is progress only when the target content hash changes. Tool success text alone is not evidence.
- Reject edits whose before and after content are identical with `NO_OP_EDIT`.
- Stop a worker after two consecutive identical tool calls or two consecutive mutating calls that produce no filesystem-content change. Report `TOOL_LOOP_DETECTED` and preserve the current worktree.
- After a mutation, reread the affected region or inspect the diff before issuing another mutation to the same target.
- Runtime guard termination is `ABORTED`, not a semantic repair. Send the observed state to Codex to decide whether to resume, re-plan, or block.

## Stack-specific rules
- Read `stack-detection.md` during BASELINE, inspect markers only inside the validated target repository, and load only matching engine/language/platform rules that exist.
- Load project-local `AGENTS.md` independently. Task- or product-specific acceptance criteria belong in the project contract, never in shared stack rules.
- Pass the complete selected rule set to planning, implementation, repair, and review agents; do not pass unrelated stack rules.

## Minimum report
Classification and rationale; changed files; acceptance criteria status; commands and exact outcomes; unresolved findings; residual risks; suggested commit message. No commit unless requested.

## Workflow audit trail
- Every production run has a stable `run_id` and an audit directory outside the target repository at `logs/workflow-runs/<run_id>/`.
- Persist normalized stage artifacts through `Write-WorkflowAudit.ps1`; never overwrite an existing artifact. Written files are marked read-only.
- Store contracts, hashes/status, selected rules, changed paths, bounded diffs or evidence, command/exit-code summaries, verdicts, and counters.
- When usage metadata is available, store input, cached-input, output, and total tokens by role/provider/model. Mark unavailable fields `null`; never estimate them inside the audit record.
- Do not store credentials, environment secrets, provider authentication, hidden reasoning, full provider prompts, unrelated source files, or unbounded command logs.
- The audit trail is evidence, not authority: current repository state and rerun validators remain authoritative.
