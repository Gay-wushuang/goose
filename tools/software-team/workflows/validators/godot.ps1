param([Parameter(Mandatory = $true)][string]$RepositoryPath,[string]$GodotExecutable)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepositoryPath).Path
$projectFile = Join-Path $repo 'project.godot'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw 'project.godot was not found.' }
if (-not $GodotExecutable) {
    $candidate = Get-ChildItem (Split-Path -Parent $repo) -Filter '*Godot*console*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $candidate) { $candidate = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($candidate) { $GodotExecutable=$candidate.Source }
}
if (-not $GodotExecutable -or -not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    [pscustomobject]@{protocol='PREFLIGHT_RESULT_V1';validator='godot';status='UNAVAILABLE';exit_code=$null;command=$null;output='Godot executable was not supplied or discovered.'} | ConvertTo-Json
    exit 3
}
if ($staticErrors.Count -gt 0) {
    [pscustomobject]@{protocol='PREFLIGHT_RESULT_V1';validator='godot';status='FAIL';exit_code=1;process_exit_codes=$null;commands=@();output=($staticErrors -join "`r`n")} | ConvertTo-Json -Depth 5
    exit 1
}
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$projectText = Get-Content -Raw -LiteralPath $projectFile
$mainMatch = [regex]::Match($projectText, '(?m)^run/main_scene\s*=\s*"res://(.+?)"\s*$')
$staticErrors = @()
if (-not $mainMatch.Success) {
    $staticErrors += 'project.godot does not declare run/main_scene.'
} else {
    $mainScene = Join-Path $repo ($mainMatch.Groups[1].Value -replace '/', '\')
    if (-not (Test-Path -LiteralPath $mainScene -PathType Leaf)) {
        $staticErrors += "Configured main scene does not exist: $mainScene"
    } else {
        $firstMeaningful = Get-Content -LiteralPath $mainScene | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($firstMeaningful -notmatch '^\[(gd_scene|gd_resource)\b') {
            $staticErrors += "Invalid Godot text-resource header in main scene: $firstMeaningful"
        }
    }
}
$editorOutput = & $GodotExecutable --headless --editor --path $repo --quit 2>&1 | Out-String
$editorCode=$LASTEXITCODE
$runOutput = & $GodotExecutable --headless --path $repo --quit-after 1 2>&1 | Out-String
$runCode=$LASTEXITCODE
$output = (($staticErrors -join "`r`n") + "`r`n" + $editorOutput + "`r`n" + $runOutput).Trim()
$ErrorActionPreference = $previousErrorAction
$hasEngineError = $output -match '(?im)^\s*(SCRIPT ERROR:|ERROR:)|Parse Error:'
$validatorCode = if ($staticErrors.Count -gt 0 -or $editorCode -ne 0 -or $runCode -ne 0 -or $hasEngineError) { 1 } else { 0 }
[pscustomobject]@{protocol='PREFLIGHT_RESULT_V1';validator='godot';status=$(if($validatorCode -eq 0){'PASS'}else{'FAIL'});exit_code=$validatorCode;process_exit_codes=@{editor=$editorCode;run=$runCode};commands=@("`"$GodotExecutable`" --headless --editor --path `"$repo`" --quit","`"$GodotExecutable`" --headless --path `"$repo`" --quit-after 1");output=$output} | ConvertTo-Json -Depth 5
exit $validatorCode
