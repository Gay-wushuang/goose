# Shadow Router V1

Shadow Router records an operator-selected tier and role, extracts traceable
risk evidence, and produces a non-binding recommendation. It does not change
the recipe, provider, model, or execution path.

## Launcher usage

```powershell
& "$env:GOOSE_SUPPORT\Run-Software-Team.cmd" `
  "Add pause behavior" `
  "E:\path\to\repository" `
  "No commit or push" `
  -Tier L1_PLUS `
  -Role primary-worker-26b
```

Accepted tiers are `UNSPECIFIED`, `L0`, `L1`, `L1_PLUS`, `L2`, and `L3`.
The default is `UNSPECIFIED` so existing invocations remain non-interactive.

## Evidence contract

Every feature includes the matched text, its source, a stable pattern id, and
the versioned rule that produced it. Recommendations reference feature ids and
always set `binding` to `false`.

The manifest is `risk-features.json`. Rule changes must increment the relevant
rule version. Do not replace evidence with an unexplained feature label.

## Ledger

Raw events are appended to:

```text
<support-directory>\logs\shadow-router\tasks.jsonl
```

A review-friendly table is appended to:

```text
<support-directory>\logs\shadow-router\task-routing.csv
```

The JSONL file is the source of truth. It contains the complete prompt,
constraints, evidence, human choice, recommendation, and a separate completion
event with Goose exit code and runtime. Keep it local when prompts contain
private repository information.

## Render smoke test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File <support-directory>\scripts\Run-Software-Team.ps1 `
  -Goal "Router smoke test" `
  -RepositoryPath <absolute-repository-path> `
  -RenderOnly
```
