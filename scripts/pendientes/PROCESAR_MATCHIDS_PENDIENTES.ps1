param(
    [string]$CsvPath,
    [int]$Limit = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$workspace = $Config.WORKSPACE
$reportRoot = $Config.REPORT_DIR
$python = Join-Path $workspace 'python-pyppeter\.venv\Scripts\python.exe'
$pipeline = Join-Path $workspace 'python\process_pending_match_csvs.py'
$auditRunUri = "$($Config.AUDIT_URL)/run"
$runId = Get-Date -Format 'yyyyMMddHHmmss'

function Get-LatestPendingRows {
    Write-Host 'Consultando el modulo persistente de auditoria...' -ForegroundColor Cyan
    $snapshot = Invoke-RestMethod -Method Post -Uri $auditRunUri -TimeoutSec 60
    if ($snapshot.status -ne 'COMPLETED') { throw "La auditoria devolvio estado $($snapshot.status): $($snapshot.error)" }

    $rows = @($snapshot.pendingMatches | ForEach-Object {
        [pscustomobject]@{
            match_date = $_.matchDate; country = $_.country; competition = $_.competition; match_id = $_.matchId
            home_team = $_.homeTeam; away_team = $_.awayTeam; pending_datasets = ($_.pendingDatasets -join ',')
        }
    })
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $pendingPath = Join-Path $reportRoot "FIXTURES_PROCESSING_AUDIT_PENDING_$stamp.csv"
    if ($rows.Count) {
        $rows | Export-Csv -LiteralPath $pendingPath -NoTypeInformation -Encoding UTF8
    } else {
        '"match_date","country","competition","match_id","home_team","away_team","pending_datasets"' |
            Set-Content -LiteralPath $pendingPath -Encoding UTF8
    }
    Write-Host ("Auditoria actualizada {0}; pendientes: {1}; lista: {2}" -f $snapshot.refreshedAt, $rows.Count, $pendingPath) -ForegroundColor Cyan
    return $rows
}

function Get-MatchKey($row) {
    return ('{0}|{1}|{2}' -f $row.country.ToLowerInvariant(), $row.competition.ToLowerInvariant(), $row.match_id)
}

if ($Limit -lt 0) { throw 'El limite debe ser 0 (todos) o un entero positivo.' }
if (-not (Test-Path -LiteralPath $python)) { throw "No existe Python: $python" }
if (-not (Test-Path -LiteralPath $pipeline)) { throw "No existe el pipeline por match_id: $pipeline" }

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
& (Join-Path $PSScriptRoot '..\arranque\ASEGURAR_SERVICIOS.ps1') -Servicios antibloqueo,postgres,auditoria,launcher,navegador
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron asegurar los servicios: antibloqueo,postgres,auditoria,launcher,navegador.' }

# Siempre se calcula el trabajo desde una auditoria nueva. Un CSV indicado por
# el usuario solo limita la seleccion; nunca puede reintroducir partidos ya completos.
$freshRows = @(Get-LatestPendingRows)
if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "No existe el CSV indicado: $CsvPath" }
    $required = @('country','competition','match_id')
    $selectionRows = @(Import-Csv -LiteralPath $CsvPath)
    if (-not $selectionRows.Count) { throw "El CSV indicado no contiene filas: $CsvPath" }
    $headers = @($selectionRows[0].PSObject.Properties.Name)
    $missingHeaders = @($required | Where-Object { $_ -notin $headers })
    if ($missingHeaders.Count) { throw "Faltan columnas obligatorias en el CSV indicado: $($missingHeaders -join ', ')" }
    $selectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($selected in $selectionRows) { [void]$selectedKeys.Add((Get-MatchKey $selected)) }
    $freshRows = @($freshRows | Where-Object { $selectedKeys.Contains((Get-MatchKey $_)) })
}

# FILTRO_PAIS / FILTRO_COMPETICION (config\basketball.env): vacios = todas las ligas.
$countryFilter = @("$($Config.FILTRO_PAIS)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$competitionFilter = @("$($Config.FILTRO_COMPETICION)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($countryFilter.Count -or $competitionFilter.Count) {
    $freshRows = @($freshRows | Where-Object {
        (-not $countryFilter.Count -or $_.country -in $countryFilter) -and
        (-not $competitionFilter.Count -or $_.competition -in $competitionFilter)
    })
    Write-Host "Filtro de ligas: pais=$($Config.FILTRO_PAIS) competicion=$($Config.FILTRO_COMPETICION); pendientes tras filtrar: $($freshRows.Count)" -ForegroundColor Cyan
}

$queue = @($freshRows | Where-Object {
    $_.match_id -match '^[A-Za-z0-9]+$' -and $_.country -match '^[a-z0-9][a-z0-9-]*$' -and $_.competition -match '^[a-z0-9][a-z0-9-]*$'
} | Group-Object country,competition,match_id | ForEach-Object { $_.Group | Select-Object -First 1 })
if ($Limit -gt 0) { $queue = @($queue | Select-Object -First $Limit) }
if (-not $queue.Count) {
    Write-Host 'La auditoria fresca no devuelve partidos que procesar. No se lanzara ninguna extraccion.' -ForegroundColor Green
    exit 0
}

Write-Host "Procesamiento secuencial: $($queue.Count) partidos pendientes segun la auditoria fresca." -ForegroundColor Cyan

$state = [System.Collections.Generic.List[object]]::new()
$currentPending = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($pendingRow in $freshRows) { [void]$currentPending.Add((Get-MatchKey $pendingRow)) }
foreach ($row in $queue) {
    $logPath = Join-Path $reportRoot ("PROCESAR_MATCHIDS_{0}_{1}.log" -f $runId, $row.match_id)
    $started = Get-Date
    try {
        if (-not $currentPending.Contains((Get-MatchKey $row))) {
            $state.Add([pscustomobject]@{
                run_id = $runId; match_date = $row.match_date; country = $row.country; competition = $row.competition; match_id = $row.match_id
                home_team = $row.home_team; away_team = $row.away_team; requested_datasets = $row.pending_datasets; status = 'SKIPPED_ALREADY_PROCESSED'
                started_at = $started.ToString('o'); finished_at = (Get-Date).ToString('o'); message = 'La auditoria fresca ya no marca este partido como pendiente.'; log = $logPath
            })
            Write-Host "[$($row.match_id)] omitido: ya no figura como pendiente en la auditoria fresca." -ForegroundColor Green
            continue
        }
        Write-Host "[$($row.country)/$($row.competition)] $($row.match_id): $($row.home_team) vs $($row.away_team)" -ForegroundColor Cyan
        $datasets = @($row.pending_datasets -split ',' | Where-Object { $_ -in @('MATCH_SUMMARY','TEAM_STATS','PLAYER_STATS','POINT_BY_POINT') })
        if (-not $datasets.Count) { throw "No hay datasets detallados procesables para $($row.match_id): $($row.pending_datasets)" }
        & $python -u $pipeline $row.match_id $row.country $row.competition $datasets 2>&1 | Tee-Object -FilePath $logPath
        if ($LASTEXITCODE -ne 0) { throw "process_pending_match_csvs.py termino con codigo $LASTEXITCODE" }
        $status = 'COMPLETED'
        $message = 'Solo datasets pendientes extraidos e importados mediante el launcher.'
    } catch {
        $status = 'ERROR'
        $message = $_.Exception.Message
        Add-Content -LiteralPath (Join-Path $reportRoot "PROCESAR_MATCHIDS_ERRORES_$runId.log") -Encoding utf8 -Value ("[{0:O}] ERROR match_id={1} country={2} competition={3} message={4}" -f (Get-Date), $row.match_id, $row.country, $row.competition, $message)
        Write-Warning "[$($row.match_id)] $message"
    }
    $state.Add([pscustomobject]@{
        run_id = $runId; match_date = $row.match_date; country = $row.country; competition = $row.competition; match_id = $row.match_id
        home_team = $row.home_team; away_team = $row.away_team; requested_datasets = $row.pending_datasets; status = $status
        started_at = $started.ToString('o'); finished_at = (Get-Date).ToString('o'); message = $message; log = $logPath
    })

    # Relee fixtures y las cinco tablas despues de cada partido; la siguiente
    # iteracion solo sigue considerando partidos aun pendientes.
    try {
        $refreshedRows = @(Get-LatestPendingRows)
        $currentPending = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($pendingRow in $refreshedRows) { [void]$currentPending.Add((Get-MatchKey $pendingRow)) }
    } catch {
        Add-Content -LiteralPath (Join-Path $reportRoot "PROCESAR_MATCHIDS_ERRORES_$runId.log") -Encoding utf8 -Value ("[{0:O}] ERROR auditoria_despues_match_id={1} message={2}" -f (Get-Date), $row.match_id, $_.Exception.Message)
        Write-Warning "No se pudo refrescar la auditoria despues de $($row.match_id): $($_.Exception.Message)"
    }
}

$statePath = Join-Path $reportRoot "PROCESAR_MATCHIDS_$runId.csv"
$state | Export-Csv -LiteralPath $statePath -NoTypeInformation -Encoding utf8
Write-Host "Resumen de ejecucion: $statePath" -ForegroundColor Cyan

Write-Host 'Refrescando auditoria final...' -ForegroundColor Cyan
$finalPending = @(Get-LatestPendingRows)

$errors = @($state | Where-Object { $_.status -eq 'ERROR' }).Count
$completed = @($state | Where-Object { $_.status -eq 'COMPLETED' }).Count
$skipped = @($state | Where-Object { $_.status -eq 'SKIPPED_ALREADY_PROCESSED' }).Count
Write-Host "Proceso terminado. Completados: $completed; omitidos por auditoria fresca: $skipped; errores: $errors." -ForegroundColor Green
exit 0
