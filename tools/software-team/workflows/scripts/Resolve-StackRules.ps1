param([Parameter(Mandatory = $true)][string]$RepositoryPath)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $repository -PathType Container)) { throw 'RepositoryPath must be a directory.' }
$rulesRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\rules')).Path
$selected = @()

foreach ($manifestPath in Get-ChildItem -LiteralPath $rulesRoot -Filter manifest.yaml -File -Recurse) {
    $lines = Get-Content -LiteralPath $manifestPath.FullName
    $id = (($lines | Select-String '^id:\s*(.+)$').Matches.Groups[1].Value).Trim(' "')
    $kind = (($lines | Select-String '^kind:\s*(.+)$').Matches.Groups[1].Value).Trim(' "')
    $ruleName = (($lines | Select-String '^rule:\s*(.+)$').Matches.Groups[1].Value).Trim(' "')
    if (-not $id -or -not $kind -or -not $ruleName) { throw "Invalid manifest: $($manifestPath.FullName)" }

    $sections = @{ all_files=@(); all_directories=@(); any_globs=@(); validators=@() }
    $section = $null
    foreach ($line in $lines) {
        if ($line -match '^\s{2}(all_files|all_directories|any_globs):\s*$') { $section=$Matches[1]; continue }
        if ($line -match '^validators:\s*$') { $section='validators'; continue }
        if ($line -match '^\s+-\s+(.+?)\s*$' -and $section) { $sections[$section] += $Matches[1].Trim(' "') }
        elseif ($line -match '^\S' -and $line -notmatch '^(detect|validators):') { $section=$null }
    }
    $hasDetection = ($sections.all_files.Count + $sections.all_directories.Count + $sections.any_globs.Count) -gt 0
    if (-not $hasDetection) { continue }
    $matched = $true
    foreach ($marker in $sections.all_files) { if (-not (Test-Path -LiteralPath (Join-Path $repository $marker) -PathType Leaf)) { $matched=$false } }
    foreach ($marker in $sections.all_directories) { if (-not (Test-Path -LiteralPath (Join-Path $repository $marker) -PathType Container)) { $matched=$false } }
    if ($sections.any_globs.Count) {
        $globMatched = $false
        foreach ($glob in $sections.any_globs) { if (Get-ChildItem -Path (Join-Path $repository $glob) -File -ErrorAction SilentlyContinue | Select-Object -First 1) { $globMatched=$true } }
        if (-not $globMatched) { $matched=$false }
    }
    if ($matched) {
        $packageRoot = $manifestPath.Directory.FullName
        $validators = @($sections.validators | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $packageRoot $_)) })
        $selected += [pscustomobject]@{ id=$id; kind=$kind; rule=[System.IO.Path]::GetFullPath((Join-Path $packageRoot $ruleName)); validators=$validators }
    }
}

[pscustomobject]@{ protocol='STACK_RULE_SELECTION_V1'; repository=$repository; selected=@($selected | Sort-Object kind,id) } | ConvertTo-Json -Depth 6
