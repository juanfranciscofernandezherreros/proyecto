param(
    [ValidateSet('ALL', 'EUROLIGA', 'NBA', 'ACB', 'BSL', 'GBL', 'LEGA_A', 'LNB', 'BBL', 'LKL', 'KLS', 'WINNER')]
    [string]$League = 'ALL',
    [ValidateSet('results', 'datos', 'todo')]
    [string]$Mode = 'todo',
    [ValidateRange(1, 100)][int]$Limit = 10,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\LIGAS_BASKET.json'),
    # Reintentos de cada extraccion tras un fallo. Por defecto ninguno: se hace todo de una
    # tirada y lo que falle se recupera despues con MATCHIDS_PENDIENTES.
    [ValidateRange(0, 5)][int]$Reintentos = 0
)

# Un fallo en una liga o en un dataset no detiene el resto: se registra y se sigue.
# Al final se guardan en REPORT_DIR:
#   ligas-orquestar-resumen-<fecha>.csv     cada liga y paso con su estado
#   ligas-orquestar-pendientes-<fecha>.csv  partidos que siguen pendientes en las ligas con
#                                           fallos, listo para: MATCHIDS_PENDIENTES.bat <csv>
# Termina con codigo 1 si algo fallo.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$workspace = $Config.WORKSPACE
$python = $Config.PYTHON
$scraper = $Config.SCRAPER
$leagues = @(Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json)
$selected = if ($League -eq 'ALL') { $leagues } else { @($leagues | Where-Object { $_.code -eq $League }) }
if (-not $selected.Count) { throw "Liga no encontrada: $League" }
# FILTRO_PAIS / FILTRO_COMPETICION (config\basketball.env): vacios = todas las ligas.
$countryFilter = @("$($Config.FILTRO_PAIS)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$competitionFilter = @("$($Config.FILTRO_COMPETICION)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$selected = @($selected | Where-Object {
    (-not $countryFilter.Count -or $_.country -in $countryFilter) -and
    (-not $competitionFilter.Count -or $_.competition -in $competitionFilter)
})
if (-not $selected.Count) { throw "Ninguna liga cumple FILTRO_PAIS='$($Config.FILTRO_PAIS)' y FILTRO_COMPETICION='$($Config.FILTRO_COMPETICION)'." }
if ($countryFilter.Count -or $competitionFilter.Count) { Write-Host "Ligas filtradas: $(($selected | ForEach-Object code) -join ', ')" -ForegroundColor Cyan }

$summary = [System.Collections.Generic.List[object]]::new()

function Invoke-Bat([string]$Name, [string[]]$Arguments) {
    & (Join-Path $PSScriptRoot "..\$Name") @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name termino con codigo $LASTEXITCODE" }
}

# Ejecuta un paso, lo reintenta si se pide y deja constancia en el resumen.
# Devuelve $true si termino bien.
function Invoke-Step([string]$Code, [string]$Step, [scriptblock]$Action, [int]$Retries = 0) {
    $started = Get-Date
    for ($attempt = 1; $attempt -le $Retries + 1; $attempt++) {
        try {
            & $Action
            $summary.Add([pscustomobject]@{ Liga = $Code; Paso = $Step; Estado = 'OK'; Intentos = $attempt
                Segundos = [int]((Get-Date) - $started).TotalSeconds; Detalle = '' })
            return $true
        } catch {
            $message = $_.Exception.Message
            if ($attempt -le $Retries) {
                Write-Host "[REINTENTO] [$Code] $Step fallo ($message); nuevo intento en 15 s." -ForegroundColor Yellow
                Start-Sleep -Seconds 15
            }
        }
    }
    Write-Host "[FALLO] [$Code] $Step`: $message" -ForegroundColor Red
    $summary.Add([pscustomobject]@{ Liga = $Code; Paso = $Step; Estado = 'FALLO'; Intentos = $Retries + 1
        Segundos = [int]((Get-Date) - $started).TotalSeconds; Detalle = $message })
    return $false
}

function Add-Skipped([string]$Code, [string]$Step, [string]$Reason) {
    Write-Host "[OMITIDO] [$Code] $Step`: $Reason" -ForegroundColor DarkYellow
    $summary.Add([pscustomobject]@{ Liga = $Code; Paso = $Step; Estado = 'OMITIDO'; Intentos = 0; Segundos = 0; Detalle = $Reason })
}

if ($Mode -in @('results', 'todo')) {
    foreach ($item in $selected) {
        Write-Host "RESULTS [$($item.code)]" -ForegroundColor Cyan
        $root = Join-Path $Config.COMPETITIONS_DIR "$($item.country)\$($item.competition)"
        $csvRef = @{}
        $extracted = Invoke-Step $item.code 'RESULTS extraer' -Retries $Reintentos {
            New-Item -ItemType Directory -Force -Path $root | Out-Null
            $started = Get-Date
            & $python $scraper --no-headless competition results $item.resultsUrl --output (Join-Path $root 'RESULTS.csv')
            if ($LASTEXITCODE -ne 0) { throw "el scraper termino con codigo $LASTEXITCODE" }
            $csvRef.File = Get-ChildItem -LiteralPath $root -File -Filter "RESULTS_*_$($item.country)_$($item.competition).csv" |
                Where-Object { $_.LastWriteTime -ge $started } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $csvRef.File) { throw 'no se genero el CSV de RESULTS' }
        }
        if ($extracted) {
            [void](Invoke-Step $item.code 'RESULTS importar' {
                Invoke-Bat 'importar\IMPORTAR_RESULTADOS.bat' @($csvRef.File.FullName, $item.country, $item.competition)
            })
        } else {
            Add-Skipped $item.code 'RESULTS importar' 'la extraccion fallo'
        }
    }
}

if ($Mode -in @('datos', 'todo')) {
    # Antibloqueo y monitor de CSV son ayudas: si fallan, se avisa y se sigue.
    [void](Invoke-Step 'GENERAL' 'antibloqueo y monitor CSV' {
        Invoke-Bat 'arranque\INICIAR_ANTIBLOQUEO.bat' @()
        Invoke-Bat 'arranque\INICIAR_WATCHER_CSV.bat' @()
    })
    $datasets = @(
        @{ Name = 'POINT_BY_POINT'; Extract = 'extraer\EXTRAER_POINT_BY_POINT.bat'; Import = 'importar\IMPORTAR_POINT_BY_POINT.bat' },
        @{ Name = 'TEAM_STATS';     Extract = 'extraer\EXTRAER_TEAM_STATS.bat';     Import = 'importar\IMPORTAR_TEAM_STATS.bat' },
        @{ Name = 'PLAYER_STATS';   Extract = 'extraer\EXTRAER_PLAYER_STATS.bat';   Import = 'importar\IMPORTAR_PLAYER_STATS.bat' }
    )
    foreach ($item in $selected) {
        Write-Host "DATOS [$($item.code)]" -ForegroundColor Cyan
        $extractArgs = @($item.country, $item.competition, $Limit)
        foreach ($dataset in $datasets) {
            $extracted = Invoke-Step $item.code "$($dataset.Name) extraer" -Retries $Reintentos {
                Invoke-Bat $dataset.Extract $extractArgs
            }
            # Si la extraccion falla no hay CSV nuevos que importar; se pasa al siguiente dataset.
            if ($extracted) {
                [void](Invoke-Step $item.code "$($dataset.Name) importar" {
                    Invoke-Bat $dataset.Import @($item.country, $item.competition)
                })
            } else {
                Add-Skipped $item.code "$($dataset.Name) importar" 'la extraccion fallo'
            }
        }
    }
}

# ---------- Resumen ----------
$failed = @($summary | Where-Object Estado -eq 'FALLO')
$reportFile = Join-Path $Config.REPORT_DIR ("ligas-orquestar-resumen-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Config.REPORT_DIR | Out-Null
$summary | Export-Csv -LiteralPath $reportFile -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '==================== RESUMEN ====================' -ForegroundColor Cyan
$summary | Format-Table Liga, Paso, Estado, Intentos, Segundos -AutoSize | Out-String -Width 200 | Write-Host
$ok = @($summary | Where-Object Estado -eq 'OK').Count
$skipped = @($summary | Where-Object Estado -eq 'OMITIDO').Count
Write-Host ("Pasos: {0} OK, {1} con fallo, {2} omitidos. Detalle: {3}" -f $ok, $failed.Count, $skipped, $reportFile)
if (-not $failed.Count) { exit 0 }

Write-Host 'Fallos:' -ForegroundColor Red
$failed | ForEach-Object { Write-Host "  [$($_.Liga)] $($_.Paso): $($_.Detalle)" -ForegroundColor Red }

# Partidos a recuperar: una auditoria nueva dice que les falta algo; se filtran a las ligas con fallos.
try {
    $failedLeagues = @($selected | Where-Object { $_.code -in @($failed.Liga) })
    $keys = @($failedLeagues | ForEach-Object { "$($_.country)|$($_.competition)" })
    $audit = Invoke-RestMethod -Method Post -Uri "$($Config.AUDIT_URL)/run" -TimeoutSec 120
    $rows = @($audit.pendingMatches | Where-Object { "$($_.country)|$($_.competition)" -in $keys } | ForEach-Object {
        [pscustomobject]@{ match_date = $_.matchDate; country = $_.country; competition = $_.competition; match_id = $_.matchId
            home_team = $_.homeTeam; away_team = $_.awayTeam; pending_datasets = ($_.pendingDatasets -join ',') } })
    $pendingFile = $reportFile -replace 'resumen', 'pendientes'
    $rows | Export-Csv -LiteralPath $pendingFile -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host ("{0} partidos pendientes en las ligas con fallos: {1}" -f $rows.Count, $pendingFile) -ForegroundColor Yellow
    Write-Host "Para recuperarlos: 1_EJECUTAR\MATCHIDS_PENDIENTES.bat `"$pendingFile`"" -ForegroundColor Yellow
} catch {
    Write-Host "No se pudo generar la lista de pendientes ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host 'Se pueden recuperar igualmente con 1_EJECUTAR\MATCHIDS_PENDIENTES.bat (procesa todos los pendientes).' -ForegroundColor Yellow
}
exit 1
