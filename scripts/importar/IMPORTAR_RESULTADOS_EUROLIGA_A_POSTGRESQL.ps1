param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [ValidatePattern('^[a-z0-9_-]+$')]
    [string]$Country = 'europe',
    [ValidatePattern('^[a-z0-9_-]+$')]
    [string]$Competition = 'euroleague'
)

$ErrorActionPreference = 'Stop'

$root = 'C:\Develop\basketball'
$pythonRoot = Join-Path $root 'python-pyppeter'
$batchRoot = Join-Path $root 'csv-extra-batch'
$launcherRoot = Join-Path $batchRoot 'launcher'
$python = Join-Path $pythonRoot '.venv\Scripts\python.exe'
$competitionRoot = "C:\data\basketball\competitions\$Country\$Competition"
$reportRoot = "C:\data\basketball\reports\$Country\$Competition"
$composeFile = Join-Path $root 'local-validation\docker-compose.yml'
$runId = Get-Date -Format 'yyyyMMddHHmmss'
$launcherUrl = 'http://localhost:8088'

function Get-CsvType([string]$name) {
    if ($name -match '^RESULTS_') { return 'RESULTS' }
    if ($name -match '^FIXTURES_') { return 'FIXTURES' }
    if ($name -match '^(SCORE_SUMMARY|MATCH_SUMMARY)_') { return 'SCORE_SUMMARY' }
    if ($name -match '^STATS_ALL_PERIODS_') { return 'STATS_ALL_PERIODS' }
    if ($name -match '^PLAYER_STATS_') { return 'PLAYER_STATS' }
    if ($name -match '^POINT_BY_POINT_') { return 'POINT_BY_POINT' }
    return $null
}

function Submit-Csv($item) {
    $body = @{ file = $item.File.FullName } | ConvertTo-Json -Compress
    $request = Invoke-RestMethod -Method Post -Uri "$launcherUrl/batch-launches" -ContentType 'application/json' -Body $body
    $deadline = (Get-Date).AddMinutes(30)
    do {
        if ($request.status -in @('COMPLETED', 'FAILED')) { return $request }
        Start-Sleep -Seconds 2
        $request = Invoke-RestMethod -Uri "$launcherUrl/batch-launches/$($request.requestId)"
    } while ($request.status -in @('QUEUED', 'RUNNING') -and (Get-Date) -lt $deadline)
    return $request
}

foreach ($path in @($python, $composeFile)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Falta un archivo necesario: $path" }
}
if (-not (Test-Path -LiteralPath $competitionRoot -PathType Container)) { throw "No existe la carpeta canonica: $competitionRoot" }
if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "No existe el CSV indicado: $CsvPath" }
$csv = Get-Item -LiteralPath $CsvPath
if ($csv.DirectoryName -ne $competitionRoot -or $csv.Name -notmatch "^RESULTS_\d{14}_$([regex]::Escape($Country))_$([regex]::Escape($Competition))\.csv$") {
    throw "El fichero indicado no es un RESULTS de $Country/$Competition dentro de la ruta canonica: $CsvPath"
}
$resultRows = @(Import-Csv -LiteralPath $csv.FullName)
if ($resultRows.Count -eq 0) { throw "El CSV no contiene resultados: $($csv.FullName)" }
$requiredQuarterColumns = @('home_score1', 'home_score2', 'home_score3', 'home_score4', 'away_score1', 'away_score2', 'away_score3', 'away_score4')
$missingQuarters = @($resultRows | Where-Object {
    $row = $_
    $row.homeScore -eq '' -or $row.awayScore -eq '' -or
    @($requiredQuarterColumns | Where-Object {
        $column = $_
        [string]::IsNullOrWhiteSpace($row.PSObject.Properties[$column].Value)
    }).Count -gt 0
})
if ($missingQuarters.Count -gt 0) {
    throw "El CSV tiene $($missingQuarters.Count) partidos sin marcador o sin los cuatro parciales reglamentarios."
}

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
Write-Host "CSV de Euroliga seleccionado: $($csv.FullName)"

& (Join-Path $PSScriptRoot '..\arranque\ASEGURAR_SERVICIOS.ps1') -Servicios postgres,launcher
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron asegurar los servicios: postgres,launcher.' }

$order = @('RESULTS', 'FIXTURES', 'SCORE_SUMMARY', 'STATS_ALL_PERIODS', 'PLAYER_STATS', 'POINT_BY_POINT')
$type = Get-CsvType $csv.Name
if (-not $type) { throw "CSV no reconocido: $($csv.FullName)" }
$files = @([pscustomobject]@{ File = $csv; Type = $type; Position = [array]::IndexOf($order, $type) })

$report = @()
foreach ($item in $files) {
    Write-Host "Enviando $($item.Type): $($item.File.Name)"
    $result = Submit-Csv $item
    $report += [pscustomobject]@{ File = $item.File.Name; Type = $item.Type; Status = $result.status; RequestId = $result.requestId }
    if ($result.status -ne 'COMPLETED') { break }
}

$batchReport = Join-Path $reportRoot "postgresql-import-$runId.csv"
$report | Export-Csv -LiteralPath $batchReport -NoTypeInformation -Encoding UTF8
$report | Format-Table -AutoSize
$incomplete = @($report | Where-Object { $_.Status -ne 'COMPLETED' })
if (@($report).Count -eq 0 -or $incomplete.Count -gt 0) {
    throw "Una o mas importaciones no terminaron en COMPLETED. Informe: $batchReport"
}

$matchIds = @(Import-Csv -LiteralPath $csv.FullName | ForEach-Object {
    if ($_.match_id) { $_.match_id } else { $_.matchId }
} | Where-Object { $_ -match '^[A-Za-z0-9_-]+$' } | Select-Object -Unique)
if ($matchIds.Count -eq 0) { throw 'No se pudieron leer match IDs para verificar la importacion.' }
$sqlIds = ($matchIds | ForEach-Object { "'$_'" }) -join ','
$query = "SELECT COUNT(DISTINCT match_id) FROM results.results WHERE country = '$Country' AND competition = '$Competition' AND match_id IN ($sqlIds);"
$databaseCount = & docker compose -f $composeFile exec -T postgres psql -U test -d basketball --no-psqlrc --tuples-only --no-align --command $query
if ($LASTEXITCODE -ne 0) { throw 'La importacion se completo, pero fallo la consulta de verificacion en PostgreSQL.' }
$databaseCount = [int](($databaseCount | Select-Object -Last 1).Trim())
Write-Host "Verificacion PostgreSQL: $databaseCount de $($matchIds.Count) partidos del CSV encontrados en results.results para $Country/$Competition."
if ($databaseCount -ne $matchIds.Count) { throw 'La consulta de PostgreSQL no encontro todos los partidos del CSV.' }
$countReport = Join-Path $reportRoot "postgresql-count-$runId.csv"
[pscustomobject]@{ Csv = $csv.FullName; ExpectedMatchCount = $matchIds.Count; DatabaseMatchCount = $databaseCount; Query = $query } |
    Export-Csv -LiteralPath $countReport -NoTypeInformation -Encoding UTF8
Write-Host "Importacion completa en PostgreSQL. Informe: $batchReport; conteo: $countReport"
