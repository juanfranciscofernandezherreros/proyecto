param(
    [datetime]$FromDate,
    [datetime]$ToDate
)

$ErrorActionPreference = 'Stop'
$desktopRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$leagues = Get-Content -Raw (Join-Path $desktopRoot 'LIGAS_BASKET.json') | ConvertFrom-Json

if ($FromDate -or $ToDate) {
    if (-not $FromDate -or -not $ToDate) { throw 'Debes indicar FromDate y ToDate juntos.' }
    if ($FromDate.Date -gt $ToDate.Date) { throw 'FromDate no puede ser posterior a ToDate.' }
}

$extractionFailures = @()
$importFailures = @()
$pendingImports = @()
Write-Host "FASE 1/2: extrayendo $(@($leagues).Count) ligas." -ForegroundColor Cyan

foreach ($league in $leagues) {
    try {
        $parameters = @{ League = $league.code; SkipImport = $true }
        if ($FromDate) { $parameters.FromDate = $FromDate; $parameters.ToDate = $ToDate }
        $result = & (Join-Path $desktopRoot 'scripts\ligas\EJECUTAR_LIGA_BASKET.ps1') @parameters
        if ($result.AlreadyProcessed) {
            Write-Host "OMITIDA: $($league.code), ya procesada hoy." -ForegroundColor DarkYellow
        } else {
            $pendingImports += $result
            Write-Host "EXTRAIDA: $($league.code) -> $($result.CsvPath)" -ForegroundColor Green
        }
    } catch {
        $extractionFailures += $league.code
        Write-Host "ERROR DE EXTRACCION [$($league.code)]: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "FASE 2/2: importando $($pendingImports.Count) CSV generados." -ForegroundColor Cyan
foreach ($result in $pendingImports) {
    try {
        $processor = Join-Path $desktopRoot 'scripts\importar\IMPORTAR_RESULTADOS.bat'
        & $processor $result.CsvPath $result.Country $result.Competition
        if ($LASTEXITCODE -ne 0) { throw "El BAT de procesado termino con codigo $LASTEXITCODE." }
        @{ generatedOn = $result.GeneratedOn; csvPath = $result.CsvPath; league = $result.League } |
            ConvertTo-Json | Set-Content -LiteralPath $result.MarkerPath -Encoding UTF8
        Write-Host "IMPORTADA: $($result.League)" -ForegroundColor Green
    } catch {
        $importFailures += $result.League
        Write-Host "ERROR DE IMPORTACION [$($result.League)]: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Resumen: extraccion fallida=$($extractionFailures.Count); importacion fallida=$($importFailures.Count); importadas=$($pendingImports.Count - $importFailures.Count)." -ForegroundColor Cyan
if ($extractionFailures.Count -gt 0 -or $importFailures.Count -gt 0) { exit 1 }
