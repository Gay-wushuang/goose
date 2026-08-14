param(
    [string]$SupportDirectory
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

if (-not $SupportDirectory) {
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Select the Goose support directory containing dist-windows, models, and llama.cpp'
    $picker.ShowNewFolderButton = $true
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
    $SupportDirectory = $picker.SelectedPath
}

$support = [System.IO.Path]::GetFullPath($SupportDirectory)
$goose = Join-Path $support 'dist-windows\resources\bin\goose.exe'
if (-not (Test-Path -LiteralPath $goose -PathType Leaf)) {
    throw "The selected directory is not a Goose support directory; missing: $goose"
}

$sourceWorkflows = Join-Path $PSScriptRoot 'workflows'
$sourceScripts = Join-Path $PSScriptRoot 'scripts'
$targetWorkflows = Join-Path $support 'workflows'
$targetScripts = Join-Path $support 'scripts'
New-Item -ItemType Directory -Force -Path $targetWorkflows, $targetScripts, (Join-Path $support 'logs') | Out-Null

Copy-Item -Path (Join-Path $sourceWorkflows '*') -Destination $targetWorkflows -Recurse -Force
Copy-Item -Path (Join-Path $sourceScripts '*') -Destination $targetScripts -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run-Software-Team.cmd') -Destination $support -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README-zh-CN.md') -Destination (Join-Path $support 'README-Software-Team.md') -Force

[System.Windows.Forms.MessageBox]::Show(
    "Installed the software-team workflow in: $support`r`n`r`nConfigure the two GGUF paths or environment variables before the first run.",
    'Software-team installation complete'
) | Out-Null
