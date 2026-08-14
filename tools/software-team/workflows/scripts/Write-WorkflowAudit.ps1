param(
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        '00-run', '01-shadow-route', '02-baseline', '03-task-plan',
        '04-e4b-handoff', '04-a4b-handoff',
        '05-e4b-report', '05-a4b-report',
        '06-preflight-0', '06-preflight-1', '06-preflight-2',
        '07-review-0', '07-review-1', '07-review-2',
        '08-repair-handoff-1', '09-repair-report-1',
        '08-repair-handoff-2', '09-repair-report-2', '10-final-report',
        '99-completion'
    )]
    [string]$Artifact,
    [Parameter(Mandatory = $true)][string]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
    throw "Workflow run directory does not exist: $RunDirectory"
}

try {
    $parsed = $Json | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Audit artifact is not valid JSON: $($_.Exception.Message)"
}

$canonical = $parsed | ConvertTo-Json -Depth 30
$target = Join-Path $RunDirectory ($Artifact + '.json')
$utf8 = [System.Text.UTF8Encoding]::new($false)

try {
    $stream = [System.IO.File]::Open(
        $target,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $utf8)
        try {
            $writer.Write($canonical)
        } finally {
            $writer.Dispose()
        }
    } finally {
        if ($stream) { $stream.Dispose() }
    }
} catch [System.IO.IOException] {
    throw "Audit artifact already exists and cannot be overwritten: $target"
}

(Get-Item -LiteralPath $target).IsReadOnly = $true
Write-Output $target
