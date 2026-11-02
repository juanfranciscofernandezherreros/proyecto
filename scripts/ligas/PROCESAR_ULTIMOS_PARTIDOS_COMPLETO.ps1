param([string]$League)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cfg = @(Get-Content -Raw (Join-Path $root 'LIGAS_BASKET.json') | ConvertFrom-Json)
if ([string]::IsNullOrWhiteSpace($League)) {
    for ($i=0; $i -lt $cfg.Count; $i++) { Write-Host ("[{0}] {1} ({2})" -f ($i+1),$cfg[$i].name,$cfg[$i].code) }
    $n = Read-Host 'Selecciona liga'
    if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $cfg.Count) { throw 'Seleccion no valida.' }
    $leagueDef = $cfg[[int]$n-1]
} else {
    $leagueDef = $cfg | Where-Object { $_.code -eq $League.ToUpperInvariant() } | Select-Object -First 1
    if (-not $leagueDef) { throw "Liga desconocida: $League" }
}

# Extrae resultados y conserva la última jornada (misma función que el flujo habitual).
$result = & (Join-Path $root 'scripts\ligas\EJECUTAR_LIGA_BASKET.ps1') -League $leagueDef.code -SkipImport
$csvPath = $result.CsvPath
$matchIds = @(Import-Csv -LiteralPath $csvPath | ForEach-Object { if ($_.matchId) {$_.matchId} else {$_.match_id} } | Where-Object { $_ -match '^[A-Za-z0-9_-]+$' } | Select-Object -Unique)
if (-not $matchIds.Count) { throw "No hay partidos válidos en $csvPath" }

$python = 'C:\Develop\basketball\python-pyppeter\.venv\Scripts\python.exe'
$scraper = 'C:\Develop\basketball\python-pyppeter\flashscore.py'
$competitionRoot = "C:\data\basketball\competitions\$($leagueDef.country)\$($leagueDef.competition)"
$reportRoot = "C:\data\basketball\reports\$($leagueDef.country)\$($leagueDef.competition)"
if (-not (Test-Path $python) -or -not (Test-Path $scraper)) { throw 'No se encuentra el scraper Python.' }
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$runLog = Join-Path $reportRoot ("last-matches-{0}.log" -f (Get-Date -Format yyyyMMddHHmmss))
foreach ($id in $matchIds) {
    Write-Host "Extrayendo bundle completo: $id"
    & $python $scraper match bundle --mid $id --data-dir $competitionRoot 2>&1 | Tee-Object -FilePath $runLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Falló la extracción del partido $id (código $LASTEXITCODE)." }
}

# Importa los CSV de la jornada en el orden que exige el launcher.
$batchRoot = 'C:\Develop\basketball\csv-extra-batch'
$launcherRoot = Join-Path $batchRoot 'launcher'
& (Join-Path $PSScriptRoot '..\arranque\ASEGURAR_SERVICIOS.ps1') -Servicios postgres,launcher
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron asegurar los servicios: postgres,launcher.' }
$prefixes=@('MATCH_DETAILS_','SCORE_SUMMARY_','STATS_ALL_PERIODS_','PLAYER_STATS_','POINT_BY_POINT_')
$types=@{ 'MATCH_DETAILS_'='MATCH_DETAILS'; 'SCORE_SUMMARY_'='SCORE_SUMMARY'; 'STATS_ALL_PERIODS_'='STATS_ALL_PERIODS'; 'PLAYER_STATS_'='PLAYER_STATS'; 'POINT_BY_POINT_'='POINT_BY_POINT' }
$report=@()
foreach ($id in $matchIds) {
    $dir=Join-Path $competitionRoot $id
    foreach ($prefix in $prefixes) {
        $file=Get-ChildItem $dir -File -Filter "$prefix*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $file) { if ($prefix -eq 'POINT_BY_POINT_') { Write-Warning "Sin PBP para $id"; continue }; throw "Falta $prefix para $id" }
        $req=Invoke-RestMethod -Method Post -Uri 'http://localhost:8088/batch-launches' -ContentType 'application/json' -Body (@{file=$file.FullName}|ConvertTo-Json -Compress)
        do { Start-Sleep 2; $req=Invoke-RestMethod -Uri "http://localhost:8088/batch-launches/$($req.requestId)" } while ($req.status -in @('QUEUED','RUNNING'))
        $report += [pscustomobject]@{MatchId=$id;Type=$types[$prefix];File=$file.Name;Status=$req.status}
        if ($req.status -ne 'COMPLETED') { throw "Falló $($file.Name): $($req.status)" }
    }
}
$report | Export-Csv (Join-Path $reportRoot "full-flow-$(Get-Date -Format yyyyMMddHHmmss).csv") -NoTypeInformation -Encoding UTF8
Write-Host "Flujo terminado para $($matchIds.Count) partidos; incluido PLAY_BY_PLAY cuando el scraper lo proporciona."
