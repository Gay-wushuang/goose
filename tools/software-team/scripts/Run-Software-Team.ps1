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
$recipe = Join-Path $supportRoot 'workflows\recipes\software-team.yaml'
$shadowRouter = Join-Path $supportRoot 'workflows\scripts\Invoke-ShadowRouter.ps1'
$auditWriter = Join-Path $supportRoot 'workflows\scripts\Write-WorkflowAudit.ps1'

function Read-RequiredValue {
    param([string]$CurrentValue, [string]$Prompt)
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue.Trim() -ne '^') {
        return $CurrentValue.Trim()
    }
    return (Read-Host $Prompt).Trim()
}

$Goal = Read-RequiredValue -CurrentValue $Goal -Prompt 'Task goal'
$RepositoryPath = Read-RequiredValue -CurrentValue $RepositoryPath -Prompt 'Absolute repository path'

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
    audit_policy = 'APPEND_ONLY_READ_ONLY_ARTIFACTS'
}
& $auditWriter -RunDirectory $runDirectory -Artifact '00-run' -Json ($runManifest | ConvertTo-Json -Depth 10 -Compress) | Out-Null
& $auditWriter -RunDirectory $runDirectory -Artifact '01-shadow-route' -Json $shadowJson | Out-Null
Write-Host ''
Write-Host 'Shadow Router (non-binding)'
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
Write-Host 'This recommendation does not change the selected workflow.'
Write-Host "Workflow run ID: $runId"
Write-Host "Audit directory: $runDirectory"

$env:GOOSE_MAX_TOOL_REPETITIONS = '2'

$arguments = @(
    'run', '--recipe', $recipe,
    '--params', "goal=$Goal",
    '--params', "repository_path=$resolvedRepository",
    '--params', "constraints=$Constraints",
    '--params', "run_id=$runId",
    '--params', "audit_directory=$runDirectory",
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
