param(
    [ValidatePattern('^[a-z0-9_-]+$')]
    [string]$Country = 'europe',
    [ValidatePattern('^[a-z0-9_-]+$')]
    [string]$Competition = 'euroleague'
)

$ErrorActionPreference = 'Stop'

$root = 'C:\Develop\basketball'
$batchRoot = Join-Path $root 'csv-extra-batch'
$launcherRoot = Join-Path $batchRoot 'launcher'
$competitionRoot = "C:\data\basketball\competitions\$Country\$Competition"
$reportRoot = "C:\data\basketball\reports\$Country\$Competition"
$composeFile = Join-Path $root 'local-validation\docker-compose.yml'
$java = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe'
$launcherJar = Join-Path $launcherRoot 'target\csv-batch-launcher.jar'
$launcherUrl = 'http://localhost:8088'
$runId = Get-Date -Format 'yyyyMMddHHmmss'

function Submit-And-Wait([System.IO.FileInfo]$File) {
    $request = Invoke-RestMethod -Method Post -Uri "$launcherUrl/batch-launches" -ContentType 'application/json' `
        -Body (@{ file = $File.FullName } | ConvertTo-Json -Compress)
    $deadline = (Get-Date).AddMinutes(15)
    do {
        Start-Sleep -Seconds 2
        $request = Invoke-RestMethod -Uri "$launcherUrl/batch-launches/$($request.requestId)"
    } while ($request.status -in @('QUEUED', 'RUNNING') -and (Get-Date) -lt $deadline)
    if ($request.status -notin @('COMPLETED', 'FAILED')) {
        throw "Tiempo de espera agotado para $($File.Name)."
    }
    return $request
}

foreach ($path in @($competitionRoot, $composeFile, $java, $launcherJar)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Falta el recurso requerido: $path" }
}
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$resultFile = Get-ChildItem -LiteralPath $competitionRoot -File -Filter "RESULTS_*_$Country`_$Competition.csv" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $resultFile) { throw "No se encontro RESULTS para $Country/$Competition." }

$matchIds = @(Import-Csv -LiteralPath $resultFile.FullName |
    ForEach-Object { $_.matchId } |
    Where-Object { $_ -match '^[A-Za-z0-9_-]+$' } |
    Select-Object -Unique)
if ($matchIds.Count -eq 0) { throw "No hay partidos validos en $($resultFile.Name)." }

$missing = @()
$files = foreach ($matchId in $matchIds) {
    # The extractor publishes one PBP CSV per match beside RESULTS. The CLI
    # adds its run ID, so select the most recently published CSV for this ID.
    $file = Get-ChildItem -LiteralPath $competitionRoot -File -Filter "POINT_BY_POINT_*$matchId.csv" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($file) {
        [pscustomobject]@{ File = $file; MatchId = $matchId }
    } else {
        $missing += $matchId
    }
}
if ($files.Count -eq 0) { throw "No hay POINT_BY_POINT para los partidos de $($resultFile.Name)." }
if ($missing.Count -gt 0) { Write-Warning "Aun no hay POINT_BY_POINT para: $($missing -join ', ')" }

Write-Host "Partidos detectados: $($matchIds.Count). CSV POINT_BY_POINT a procesar: $($files.Count)."
& (Join-Path $PSScriptRoot '..\arranque\ASEGURAR_SERVICIOS.ps1') -Servicios postgres,launcher
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron asegurar los servicios: postgres,launcher.' }

$report = foreach ($entry in $files) {
    Write-Host "Enviando: $($entry.File.Name)"
    $response = Submit-And-Wait $entry.File
    [pscustomobject]@{
        File = $entry.File.Name
        MatchId = $entry.MatchId
        RequestId = $response.requestId
        Status = $response.status
        Batch = $response.batch
    }
}

$reportPath = Join-Path $reportRoot "point-by-point-import-$runId.csv"
$report | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
$report | Format-Table -AutoSize
if (@($report | Where-Object { $_.Status -ne 'COMPLETED' }).Count -gt 0) {
    throw "Una o mas importaciones fallaron. Informe: $reportPath"
}
Write-Host "Importacion secuencial completada. Informe: $reportPath"
