# Goose local software-team workflow (unofficial)

This directory contains the installable Windows package for the unofficial
Codex + Gemma E4B + Gemma 26B A4B software-team workflow.

It includes role contracts, deterministic stack validators, versioned JSON
handoff schemas, loop-aware local-worker policies, a shadow router, and an
append-only per-run audit trail.

## Install

Run PowerShell as your normal user:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Select the Goose support directory that contains `dist-windows`, `models`, and
`llama.cpp`. The installer does not include or download GGUF weights,
`llama-server.exe`, credentials, or personal configuration.

The default model filenames are defined in `scripts/Switch-Local-Model.cmd`.
You may instead define absolute paths through:

```powershell
$env:GOOSE_E4B_MODEL = 'D:\Models\e4b.gguf'
$env:GOOSE_A4B_MODEL = 'D:\Models\a4b.gguf'
```

For the full Chinese guide, see [README-zh-CN.md](README-zh-CN.md).

This package depends on the Runtime guard changes from this fork. It is not an
official aaif-goose feature.
