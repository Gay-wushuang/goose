param([Parameter(Mandatory = $true)][string]$RepositoryPath)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepositoryPath).Path
$output = & dotnet build $repo --nologo 2>&1 | Out-String
$code=$LASTEXITCODE
[pscustomobject]@{protocol='PREFLIGHT_RESULT_V1';validator='dotnet';status=$(if($code -eq 0){'PASS'}else{'FAIL'});exit_code=$code;command="dotnet build `"$repo`" --nologo";output=$output.Trim()} | ConvertTo-Json -Depth 4
exit $code
