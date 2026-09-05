$ErrorActionPreference = 'Stop'
$sources = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'sources.json') | ConvertFrom-Json
foreach ($source in $sources) {
    $destination = Join-Path $PSScriptRoot $source.file
    if (Test-Path -LiteralPath $destination) { continue }
    try {
        Invoke-WebRequest -Uri $source.image -OutFile $destination -TimeoutSec 20
        Write-Output "$($source.file): $((Get-Item -LiteralPath $destination).Length) bytes"
    } catch {
        Write-Warning "$($source.file): $($_.Exception.Message)"
    }
}
