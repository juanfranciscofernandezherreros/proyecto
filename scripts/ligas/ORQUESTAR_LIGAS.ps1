param(
    [ValidateSet('ALL', 'EUROLIGA', 'NBA', 'ACB', 'BSL', 'GBL', 'LEGA_A', 'LNB', 'BBL', 'LKL', 'KLS', 'WINNER')]
    [string]$League = 'ALL',
    [ValidateSet('results', 'datos', 'todo')]
    [string]$Mode = 'todo',
    [ValidateRange(1, 100)][int]$Limit = 10,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\LIGAS_BASKET.json')
)

$ErrorActionPreference = 'Stop'
$workspace = 'C:\Develop\basketball'
$python = Join-Path $workspace 'python-pyppeter\.venv\Scripts\python.exe'
$scraper = Join-Path $workspace 'python-pyppeter\flashscore.py'
$leagues = @(Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json)
$selected = if ($League -eq 'ALL') { $leagues } else { @($leagues | Where-Object { $_.code -eq $League }) }
if (-not $selected.Count) { throw "Liga no encontrada: $League" }

function Start-ExtractionHelpers {
    Invoke-Bat 'arranque\INICIAR_ANTIBLOQUEO.bat' @()
    Invoke-Bat 'arranque\INICIAR_WATCHER_CSV.bat' @()
}

function Invoke-Bat([string]$Name, [string[]]$Arguments) {
    & (Join-Path $PSScriptRoot "..\$Name") @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name termino con codigo $LASTEXITCODE" }
}

if ($Mode -in @('results', 'todo')) {
    foreach ($item in $selected) {
        $root = "C:\data\basketball\competitions\$($item.country)\$($item.competition)"
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $started = Get-Date
        Write-Host "RESULTS [$($item.code)]" -ForegroundColor Cyan
        & $python $scraper --no-headless competition results $item.resultsUrl --output (Join-Path $root 'RESULTS.csv')
        if ($LASTEXITCODE -ne 0) { throw "RESULTS fallo para $($item.code)" }
        $csv = Get-ChildItem -LiteralPath $root -File -Filter "RESULTS_*_$($item.country)_$($item.competition).csv" |
            Where-Object { $_.LastWriteTime -ge $started } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $csv) { throw "No se genero RESULTS para $($item.code)" }
        Invoke-Bat 'importar\IMPORTAR_RESULTADOS.bat' @($csv.FullName, $item.country, $item.competition)
    }
}

if ($Mode -in @('datos', 'todo')) {
    Start-ExtractionHelpers
    foreach ($item in $selected) {
        $args = @($item.country, $item.competition, $Limit)
        Write-Host "DATOS [$($item.code)]" -ForegroundColor Cyan
        Invoke-Bat 'extraer\EXTRAER_POINT_BY_POINT.bat' $args
        Invoke-Bat 'importar\IMPORTAR_POINT_BY_POINT.bat' @($item.country, $item.competition)
        Invoke-Bat 'extraer\EXTRAER_TEAM_STATS.bat' $args
        Invoke-Bat 'importar\IMPORTAR_TEAM_STATS.bat' @($item.country, $item.competition)
        Invoke-Bat 'extraer\EXTRAER_PLAYER_STATS.bat' $args
        Invoke-Bat 'importar\IMPORTAR_PLAYER_STATS.bat' @($item.country, $item.competition)
    }
}
