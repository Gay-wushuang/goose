param(
    [Parameter(Mandatory = $true)][string]$Goal,
    [Parameter(Mandatory = $true)][string]$RepositoryPath,
    [string]$Constraints = '',
    [string]$HumanTier = 'UNSPECIFIED',
    [string]$HumanRole = 'UNSPECIFIED',
    [string]$ManifestPath,
    [string]$LedgerDirectory,
    [switch]$NoLedger
)

$ErrorActionPreference = 'Stop'
$workflowRoot = Split-Path -Parent $PSScriptRoot
$supportRoot = Split-Path -Parent $workflowRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $workflowRoot 'routing\risk-features.json'
}
if ([string]::IsNullOrWhiteSpace($LedgerDirectory)) {
    $LedgerDirectory = Join-Path $supportRoot 'logs\shadow-router'
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tierRank = @{ L0 = 0; L1 = 1; L1_PLUS = 2; L2 = 3; L3 = 4 }
$suggestedTier = 'L0'
$features = [System.Collections.Generic.List[object]]::new()
$featureSequence = 0

function Add-Feature {
    param(
        [object]$Rule,
        [string]$Text,
        [string]$Location,
        [string]$PatternId,
        [string]$MatchedText
    )
    $script:featureSequence++
    $featureId = 'RF-{0:D3}' -f $script:featureSequence
    $script:features.Add([ordered]@{
        feature = [string]$Rule.feature
        feature_id = $featureId
        evidence = [ordered]@{
            text = $MatchedText
            location = $Location
            matched_pattern = $PatternId
            rule_id = [string]$Rule.id
            rule_version = [string]$Rule.version
        }
        confidence = 1.0
    })
    $minimumTier = [string]$Rule.minimum_tier
    if ($script:tierRank[$minimumTier] -gt $script:tierRank[$script:suggestedTier]) {
        $script:suggestedTier = $minimumTier
    }
}

$sourceValues = @{
    user_prompt = $Goal
    constraints = $Constraints
}
foreach ($rule in $manifest.rules) {
    foreach ($source in $rule.sources) {
        $location = [string]$source
        $sourceText = [string]$sourceValues[$location]
        if ([string]::IsNullOrWhiteSpace($sourceText)) { continue }
        foreach ($pattern in $rule.patterns) {
            $match = [regex]::Match($sourceText, [string]$pattern.regex)
            if ($match.Success) {
                Add-Feature -Rule $rule -Text $sourceText -Location $location -PatternId ([string]$pattern.id) -MatchedText $match.Value
            }
        }
    }
}

foreach ($rule in $manifest.repository_rules) {
    $candidate = Join-Path $RepositoryPath ([string]$rule.relative_path)
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Add-Feature -Rule $rule -Text ([string]$rule.relative_path) -Location 'repository_scan' -PatternId ([string]$rule.pattern_id) -MatchedText ([string]$rule.relative_path)
    }
}

foreach ($rule in $manifest.combination_rules) {
    $presentFeatures = @($features | ForEach-Object { [string]$_.feature } | Select-Object -Unique)
    $requiredFeatures = @($rule.requires_all | ForEach-Object { [string]$_ })
    $missingFeatures = @($requiredFeatures | Where-Object { $_ -notin $presentFeatures })
    if ($missingFeatures.Count -eq 0) {
        $derivedEvidence = $requiredFeatures -join ' + '
        Add-Feature -Rule $rule -Text $derivedEvidence -Location 'derived_features' -PatternId ([string]$rule.pattern_id) -MatchedText $derivedEvidence
    }
}

$actionableFeatures = @($features | Where-Object { $_.feature -ne 'external_validator_available' })
if ($actionableFeatures.Count -eq 0) {
    $suggestedTier = [string]$manifest.default_tier
}

$canonicalInput = [ordered]@{
    goal = $Goal
    repository_path = $RepositoryPath
    constraints = $Constraints
}
$canonicalJson = $canonicalInput | ConvertTo-Json -Compress
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $inputHash = 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonicalJson))).Replace('-', ''))
} finally {
    $sha.Dispose()
}

$timestamp = [DateTimeOffset]::Now
$taskId = $timestamp.ToString('yyyyMMdd-HHmmss-fff')
$result = [ordered]@{
    protocol = 'SHADOW_ROUTE_V1'
    router_version = [string]$manifest.router_version
    manifest_version = [string]$manifest.manifest_version
    task_id = $taskId
    evaluated_at = $timestamp.ToString('o')
    input_hash = $inputHash
    input = [ordered]@{
        goal = $Goal
        repository_path = $RepositoryPath
        constraints = $Constraints
    }
    risk_features = @($features)
    recommendation = [ordered]@{
        tier = $suggestedTier
        derived_from = @($features | ForEach-Object { $_.feature_id })
        binding = $false
    }
    human_decision = [ordered]@{
        tier = $HumanTier
        role = $HumanRole
    }
}

if (-not $NoLedger) {
    New-Item -ItemType Directory -Force -Path $LedgerDirectory | Out-Null
    $jsonlPath = Join-Path $LedgerDirectory 'tasks.jsonl'
    $csvPath = Join-Path $LedgerDirectory 'task-routing.csv'
    ($result | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $jsonlPath -Encoding UTF8
    $featureSummary = ($features | ForEach-Object {
        '{0}:{1}@{2}' -f $_.feature, $_.evidence.matched_pattern, $_.evidence.location
    }) -join ';'
    $csvRow = [pscustomobject]@{
        task_id = $taskId
        evaluated_at = $timestamp.ToString('o')
        repository_path = $RepositoryPath
        human_tier = $HumanTier
        human_role = $HumanRole
        shadow_tier = $suggestedTier
        risk_features = $featureSummary
        input_hash = $inputHash
        goal = $Goal
        constraints = $Constraints
    }
    if (Test-Path -LiteralPath $csvPath) {
        $csvRow | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
    } else {
        $csvRow | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    }
}

$result | ConvertTo-Json -Depth 12
