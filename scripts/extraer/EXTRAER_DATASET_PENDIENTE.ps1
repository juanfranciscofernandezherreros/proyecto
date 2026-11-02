param(
    [ValidateSet('score_summary.csv', 'stats_all_periods.csv', 'player_stats.csv')]
    [string]$Dataset,
    [ValidatePattern('^[a-z0-9_-]+$')][string]$Country = 'europe',
    [ValidatePattern('^[a-z0-9_-]+$')][string]$Competition = 'euroleague',
    [ValidateRange(1, 500)][int]$Limit = 20
)

# Selenium/Pyppeteer may write warnings to stderr. In Windows PowerShell 5
# those arrive as ErrorRecord, so rely on $LASTEXITCODE after each extractor.
$ErrorActionPreference = 'Continue'
$root = 'C:\Develop\basketball\python-pyppeter'
$python = Join-Path $root '.venv\Scripts\python.exe'
$scraper = Join-Path $root 'flashscore.py'
$resolver = Join-Path $PSScriptRoot '..\..\python\resolve_flashscore_redirect.py'
$competitionRoot = "C:\data\basketball\competitions\$Country\$Competition"
$reportRoot = Join-Path $PSScriptRoot '..\..\logs'
$datasetLabels = @{
    'score_summary.csv' = 'MATCH_SUMMARY'
    'stats_all_periods.csv' = 'TEAM_STATS'
    'player_stats.csv' = 'PLAYER_STATS'
}
$datasetPrefixes = @{
    'score_summary.csv' = 'SCORE_SUMMARY'
    'stats_all_periods.csv' = 'STATS_ALL_PERIODS'
    'player_stats.csv' = 'PLAYER_STATS'
}

foreach ($path in @($python, $scraper, $resolver, $competitionRoot)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "No se encuentra: $path" }
}
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$results = Get-ChildItem -LiteralPath $competitionRoot -File -Filter "RESULTS_*_$Country`_$Competition.csv" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $results) { throw "No hay RESULTS CSV para $Country/$Competition en $competitionRoot" }
$rows = @(Import-Csv -LiteralPath $results.FullName | Where-Object {
    ($_.matchId -or $_.match_id) -and $_.eventDatetime
} | Sort-Object { [datetimeoffset]::Parse($_.eventDatetime) } -Descending | Select-Object -First $Limit)
if (-not $rows.Count) { throw "El CSV $($results.Name) no contiene partidos con ID y fecha." }

$runId = Get-Date -Format 'yyyyMMddHHmmss'
$label = $datasetLabels[$Dataset]
$prefix = $datasetPrefixes[$Dataset]
$logPath = Join-Path $reportRoot "$($label.ToLowerInvariant())-extraction-$runId.log"
Write-Host "RESULTS: $($results.FullName)"
Write-Host "Partidos a extraer: $($rows.Count) (limite $Limit)"
foreach ($row in $rows) {
    $matchId = if ($row.matchId) { $row.matchId } else { $row.match_id }
    $url = (& $python $resolver $matchId).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $url) {
        throw "Flashscore no devolvio la URL canonica para $matchId; log: $logPath"
    }
    Write-Host "[$matchId] $($row.homeTeam) - $($row.awayTeam)"
    $completed = $false
    for ($attempt = 1; $attempt -le 3 -and -not $completed; $attempt++) {
        Write-Host "[$matchId] $label intento $attempt/3"
        & $python $scraper match bundle $url --data-dir $competitionRoot --dataset $Dataset 2>&1 |
            Tee-Object -FilePath $logPath -Append
        if ($LASTEXITCODE -ne 0) { throw "La extraccion $label fallo para $matchId; log: $logPath" }
        $csv = Get-ChildItem -LiteralPath (Join-Path $competitionRoot $matchId) -File -Filter "${prefix}_*.csv" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $hasRows = $csv -and (Get-Content -LiteralPath $csv.FullName | Select-Object -Skip 1 -First 1)
        if ($hasRows) {
            $completed = $true
        } elseif ($attempt -lt 3) {
            Write-Warning "[$matchId] $label vacio; se reintentara."
        }
    }
    if (-not $completed) { Write-Warning "[$matchId] $label sigue vacio tras 3 intentos." }
}
Write-Host "Extraccion $label terminada. Log: $logPath"
