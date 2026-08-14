# Stack Rule Package Protocol

Stack detection is decentralized. Each package below `rules/engines`,
`rules/languages`, or `rules/platforms` owns a `manifest.yaml` beside its
`rule.md`. Adding a stack adds a package; it must not require editing this file.

The coordinator must run `scripts/Resolve-StackRules.ps1` against the validated
repository root. The resolver scans manifests only under the workflow rule
directory and evaluates markers only inside the target repository. Its
`STACK_RULE_SELECTION_V1` JSON is the authoritative list of rule and validator
paths to load.

Supported detection keys are `all_files`, `all_directories`, and `any_globs`.
Every specified `all_*` marker must exist. At least one `any_globs` pattern must
match when that key is present. Empty detection is invalid and never matches.

Project-local `AGENTS.md` is loaded separately. Product requirements and task
acceptance criteria never belong in a shared stack package.
