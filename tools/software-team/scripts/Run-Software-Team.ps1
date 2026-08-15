param(
    [Parameter(Position = 0)][string]$Goal,
    [Parameter(Position = 1)][string]$RepositoryPath,
    [Parameter(Position = 2)][string]$Constraints = 'Preserve existing behavior and unrelated changes. No commit or push.',
    [ValidateSet('UNSPECIFIED', 'L0', 'L1', 'L1_PLUS', 'L2', 'L3')][string]$Tier = 'UNSPECIFIED',
    [string]$Role = 'UNSPECIFIED',
    [switch]$RenderOnly
)

$ErrorActionPreference = 'Stop'
$supportRoot = Split-Path -Parent $PSScriptRoot
$goose = Join-Path $supportRoot 'dist-windows\resources\bin\goose.exe'
$shadowRouter = Join-Path $supportRoot 'workflows\scripts\Invoke-ShadowRouter.ps1'
$auditWriter = Join-Path $supportRoot 'workflows\scripts\Write-WorkflowAudit.ps1'
$modelSwitcher = Join-Path $supportRoot 'scripts\Switch-Local-Model.cmd'

function Read-RequiredValue {
    param([string]$CurrentValue, [string]$Prompt)
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue.Trim() -ne '^') {
        return $CurrentValue.Trim()
    }
    return (Read-Host $Prompt).Trim()
}

$Goal = Read-RequiredValue -CurrentValue $Goal -Prompt 'Task goal'
$RepositoryPath = Read-RequiredValue -CurrentValue $RepositoryPath -Prompt 'Absolute repository path'

if ($Tier -eq 'UNSPECIFIED') {
    Write-Host ''
    Write-Host 'Select the binding workflow entry:'
    Write-Host '  0 - L0: mechanical/local E4B (Codex 0)'
    Write-Host '  1 - L1: normal local A4B (Codex 0)'
    Write-Host '  2 - L1+: local A4B with self-check and risk gate (Codex 0)'
    Write-Host '  3 - L2: Codex architect + local worker + Codex review'
    Write-Host '  4 - L3: Codex read-only diagnosis'
    $selection = (Read-Host 'Entry [0-4]').Trim()
    $Tier = switch ($selection) {
        '0' { 'L0' }
        '1' { 'L1' }
        '2' { 'L1_PLUS' }
        '3' { 'L2' }
        '4' { 'L3' }
        default { throw "Invalid entry selection: $selection" }
    }
}

$route = switch ($Tier) {
    'L0' { @{ Recipe = 'software-team-local-fast.yaml'; Model = 'e4b'; Role = 'fast-worker-e4b' } }
    'L1' { @{ Recipe = 'software-team-local-primary.yaml'; Model = '26b'; Role = 'primary-worker-26b' } }
    'L1_PLUS' { @{ Recipe = 'software-team-local-primary.yaml'; Model = '26b'; Role = 'primary-worker-26b-risk-gated' } }
    'L2' { @{ Recipe = 'software-team.yaml'; Model = $null; Role = 'codex-architect-reviewer' } }
    'L3' { @{ Recipe = 'software-team-diagnosis.yaml'; Model = $null; Role = 'codex-diagnostician' } }
    default { throw "Unsupported binding tier: $Tier" }
}
if ($Role -eq 'UNSPECIFIED') { $Role = $route.Role }
$recipe = Join-Path $supportRoot (Join-Path 'workflows\recipes' $route.Recipe)

if ([string]::IsNullOrWhiteSpace($Goal) -or $Goal -eq '^') {
    throw 'Task goal is required. Do not pass a caret (^) as an argument.'
}
if ([string]::IsNullOrWhiteSpace($RepositoryPath) -or $RepositoryPath -eq '^') {
    throw 'Repository path is required. Do not pass a caret (^) as an argument.'
}
if (-not [System.IO.Path]::IsPathRooted($RepositoryPath)) {
    throw "Repository path must be absolute: $RepositoryPath"
}
$resolvedRepository = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedRepository -PathType Container)) {
    throw "Repository directory does not exist: $resolvedRepository"
}
if (-not (Test-Path -LiteralPath $goose -PathType Leaf)) {
    throw "Goose executable does not exist: $goose"
}
if (-not (Test-Path -LiteralPath $recipe -PathType Leaf)) {
    throw "Production software-team recipe does not exist: $recipe"
}
if ([string]::IsNullOrWhiteSpace($Constraints) -or $Constraints.Trim() -eq '^') {
    $Constraints = 'Preserve existing behavior and unrelated changes. No commit or push.'
}

Write-Host "Goal: $Goal"
Write-Host "Repository: $resolvedRepository"
Write-Host "Constraints: $Constraints"
Write-Host "Binding entry: $Tier / $Role"
Write-Host "Recipe: $($route.Recipe)"

if (-not (Test-Path -LiteralPath $shadowRouter -PathType Leaf)) {
    throw "Shadow Router does not exist: $shadowRouter"
}
$shadowJson = & $shadowRouter `
    -Goal $Goal `
    -RepositoryPath $resolvedRepository `
    -Constraints $Constraints `
    -HumanTier $Tier `
    -HumanRole $Role
$shadow = $shadowJson | ConvertFrom-Json
$runId = [string]$shadow.task_id
$runDirectory = Join-Path $supportRoot (Join-Path 'logs\workflow-runs' $runId)
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$runManifest = [ordered]@{
    protocol = 'WORKFLOW_RUN_V1'
    run_id = $runId
    started_at = [DateTimeOffset]::Now.ToString('o')
    repository_path = $resolvedRepository
    goal = $Goal
    constraints = $Constraints
    entry_tier = $Tier
    entry_role = $Role
    recipe = $route.Recipe
    audit_policy = 'APPEND_ONLY_READ_ONLY_ARTIFACTS'
}
& $auditWriter -RunDirectory $runDirectory -Artifact '00-run' -Json ($runManifest | ConvertTo-Json -Depth 10 -Compress) | Out-Null
& $auditWriter -RunDirectory $runDirectory -Artifact '01-shadow-route' -Json $shadowJson | Out-Null
Write-Host ''
Write-Host 'Shadow Router recommendation (non-binding)'
Write-Host "Human choice: $Tier / $Role"
Write-Host "Recommendation: $($shadow.recommendation.tier)"
if ($shadow.risk_features.Count -eq 0) {
    Write-Host 'Risk evidence: none matched'
} else {
    Write-Host 'Risk evidence:'
    foreach ($feature in $shadow.risk_features) {
        Write-Host ("- {0}: '{1}' ({2}, pattern={3}, rule={4}@{5})" -f `
            $feature.feature,
            $feature.evidence.text,
            $feature.evidence.location,
            $feature.evidence.matched_pattern,
            $feature.evidence.rule_id,
            $feature.evidence.rule_version)
    }
}
Write-Host "Binding route remains the human-selected $Tier entry."
Write-Host "Workflow run ID: $runId"
Write-Host "Audit directory: $runDirectory"

$env:GOOSE_MAX_TOOL_REPETITIONS = '2'

if (-not $RenderOnly -and $route.Model) {
    if (-not (Test-Path -LiteralPath $modelSwitcher -PathType Leaf)) {
        throw "Local model switcher does not exist: $modelSwitcher"
    }
    & $modelSwitcher $route.Model
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start the local model for $Tier (exit code $LASTEXITCODE)."
    }
}

$arguments = @(
    'run', '--recipe', $recipe,
    '--params', "goal=$Goal",
    '--params', "repository_path=$resolvedRepository",
    '--params', "constraints=$Constraints",
    '--params', "run_id=$runId",
    '--params', "audit_directory=$runDirectory",
    '--params', "entry_tier=$Tier",
    '--max-tool-repetitions', '2'
)
if ($RenderOnly) {
    $arguments += '--render-recipe'
} else {
    $arguments += '--interactive'
}
$startedAt = [DateTimeOffset]::Now
& $goose @arguments
$gooseExitCode = $LASTEXITCODE
$finishedAt = [DateTimeOffset]::Now
$completion = [ordered]@{
    protocol = 'SHADOW_ROUTE_COMPLETION_V1'
    task_id = $shadow.task_id
    finished_at = $finishedAt.ToString('o')
    runtime_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    goose_exit_code = $gooseExitCode
}
& $auditWriter -RunDirectory $runDirectory -Artifact '99-completion' -Json ($completion | ConvertTo-Json -Depth 10 -Compress) | Out-Null
$ledgerDirectory = Join-Path $supportRoot 'logs\shadow-router'
New-Item -ItemType Directory -Force -Path $ledgerDirectory | Out-Null
($completion | ConvertTo-Json -Compress) | Add-Content -LiteralPath (Join-Path $ledgerDirectory 'tasks.jsonl') -Encoding UTF8
exit $gooseExitCode
