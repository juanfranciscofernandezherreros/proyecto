param(
    [ValidatePattern('^[a-z0-9_-]+$')][string]$Country = 'europe',
    [ValidatePattern('^[a-z0-9_-]+$')][string]$Competition = 'euroleague',
    [ValidateRange(1, 500)][int]$Limit = 20
)

# Windows PowerShell 5 wraps native stderr as an ErrorRecord. Pyppeter sends
# deprecation notices there, so use its exit code to detect actual failures.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\config.ps1')
$root = $Config.SCRAPER_DIR
$python = Join-Path $root '.venv\Scripts\python.exe'
$scraper = Join-Path $root 'flashscore.py'
$competitionRoot = Join-Path $Config.COMPETITIONS_DIR "$Country\$Competition"
$reportRoot = Join-Path $PSScriptRoot '..\..\logs'
$chromeDriver = Join-Path $PSScriptRoot '..\..\.tools\chromedriver\chromedriver-win64\chromedriver.exe'
foreach ($path in @($python, $scraper, $competitionRoot, $chromeDriver)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "No se encuentra: $path" }
}
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$env:CHROMEDRIVER_PATH = $chromeDriver

$results = Get-ChildItem -LiteralPath $competitionRoot -File -Filter "RESULTS_*_$Country`_$Competition.csv" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $results) { throw "No hay RESULTS CSV para $Country/$Competition en $competitionRoot" }
$rows = @(Import-Csv -LiteralPath $results.FullName | Where-Object {
    ($_.matchId -or $_.match_id) -and $_.eventDatetime
} | Sort-Object { [datetimeoffset]::Parse($_.eventDatetime) } -Descending | Select-Object -First $Limit)
if (-not $rows.Count) { throw "El CSV $($results.Name) no contiene partidos con ID y fecha." }

$runId = Get-Date -Format 'yyyyMMddHHmmss'
$logPath = Join-Path $reportRoot "play-by-play-extraction-$runId.log"
Write-Host "RESULTS: $($results.FullName)"
Write-Host "Partidos a extraer: $($rows.Count) (límite $Limit)"
foreach ($row in $rows) {
    $matchId = if ($row.matchId) { $row.matchId } else { $row.match_id }
    $output = Join-Path $competitionRoot "POINT_BY_POINT_${matchId}.csv"
    $homeSlug = (($row.homeTeam.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
    $awaySlug = (($row.awayTeam.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
    $url = "https://www.flashscore.com/match/basketball/$homeSlug/$awaySlug/?mid=$matchId"
    Write-Host "[$matchId] $($row.homeTeam) - $($row.awayTeam)"
    & $python $scraper match quarters $url --mid $matchId --output $output 2>&1 |
        Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) { throw "Pyppeter falló para $matchId; log: $logPath" }
    if (-not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) {
        Write-Warning "[$matchId] No se generó CSV POINT_BY_POINT (puede no estar disponible)."
    } else {
        Write-Host "[$matchId] CSV creado: $output"
    }
}
Write-Host "Extracción terminada. Log: $logPath"
