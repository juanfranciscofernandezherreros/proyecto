param(
    [string]$League,
    [datetime]$FromDate,
    [datetime]$ToDate,
    [switch]$SkipImport
)

$ErrorActionPreference = 'Stop'

function Get-LatestMatchdayRows([object[]]$Rows) {
    $datedRows = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.eventDatetime) } | ForEach-Object {
        $_ | Add-Member -NotePropertyName _eventDate -NotePropertyValue ([datetimeoffset]::Parse($_.eventDatetime).Date) -PassThru
    })
    if ($datedRows.Count -eq 0) { throw 'El CSV no contiene resultados con fecha.' }

    $selected = [System.Collections.Generic.List[object]]::new()
    $teams = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($day in ($datedRows | Group-Object _eventDate | Sort-Object { $_.Group[0]._eventDate } -Descending)) {
        $dayRows = @($day.Group)
        $repeatsTeam = @($dayRows | Where-Object { $teams.Contains($_.homeTeam) -or $teams.Contains($_.awayTeam) }).Count -gt 0
        if ($selected.Count -gt 0 -and $repeatsTeam) { break }
        foreach ($row in $dayRows) {
            $selected.Add($row)
            [void]$teams.Add($row.homeTeam)
            [void]$teams.Add($row.awayTeam)
        }
    }
    return @($selected | Select-Object * -ExcludeProperty _eventDate)
}

$desktopRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$leagues = Get-Content -Raw (Join-Path $desktopRoot 'LIGAS_BASKET.json') | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($League)) {
    Write-Host ''
    Write-Host 'Ligas disponibles:'
    for ($index = 0; $index -lt $leagues.Count; $index++) {
        Write-Host "  $($index + 1). $($leagues[$index].name) [$($leagues[$index].code)]"
    }
    $selection = Read-Host 'Elige una liga por numero'
    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $leagues.Count) {
        throw 'Seleccion de liga no valida.'
    }
    $leagueDefinition = $leagues[[int]$selection - 1]
} else {
    $leagueDefinition = $leagues | Where-Object { $_.code -eq $League.ToUpperInvariant() } | Select-Object -First 1
    if (-not $leagueDefinition) { throw "Liga no configurada: $League" }
}

. (Join-Path $PSScriptRoot '..\config.ps1')
$python = $Config.PYTHON
$scraper = $Config.SCRAPER
$chromeDriver = Join-Path $desktopRoot '.tools\chromedriver\chromedriver-win64\chromedriver.exe'
$competitionRoot = Join-Path $Config.COMPETITIONS_DIR "$($leagueDefinition.country)\$($leagueDefinition.competition)"
$output = Join-Path $competitionRoot 'RESULTS.csv'
$logDirectory = Join-Path $desktopRoot 'logs'
$logPath = Join-Path $logDirectory ("extraccion_{0}_{1:yyyyMMdd_HHmmss}.log" -f $leagueDefinition.code, (Get-Date))
if (-not (Test-Path -LiteralPath $python)) { throw "No se encuentra Python: $python" }
if (-not (Test-Path -LiteralPath $scraper)) { throw "No se encuentra el scraper: $scraper" }
if (-not (Test-Path -LiteralPath $chromeDriver)) { throw "No se encuentra ChromeDriver: $chromeDriver" }
$env:CHROMEDRIVER_PATH = $chromeDriver
New-Item -ItemType Directory -Force -Path $competitionRoot | Out-Null
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$existingPattern = '^RESULTS_\d{14}_.+\.csv$'
$existingCsv = Get-ChildItem -LiteralPath $competitionRoot -File |
    Where-Object { $_.Name -match $existingPattern -and $_.Length -gt 0 } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$existingCsvHasResults = $false
if ($existingCsv) {
    $existingCsvHasResults = @(
        Import-Csv -LiteralPath $existingCsv.FullName |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.eventDatetime) }
    ).Count -gt 0
}
$markerPath = Join-Path $competitionRoot 'LATEST_RESULTS.json'
$today = Get-Date -Format 'yyyy-MM-dd'
if (-not $FromDate -and (Test-Path -LiteralPath $markerPath)) {
    $marker = Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json
    if ($marker.generatedOn -eq $today -and (Test-Path -LiteralPath $marker.csvPath)) {
        Write-Host "RESULTS de hoy ya procesado: $($marker.csvPath)"
        if ($SkipImport) {
            return [pscustomobject]@{
                League = $leagueDefinition.code
                Country = $leagueDefinition.country
                Competition = $leagueDefinition.competition
                CsvPath = $marker.csvPath
                AlreadyProcessed = $true
            }
        }
        return
    }
}

if ($existingCsv -and $existingCsvHasResults -and $existingCsv.LastWriteTime.Date -eq (Get-Date).Date) {
    $csv = $existingCsv
    Write-Host "Usando RESULTS generado hoy: $($csv.FullName)"
} else {
    Write-Host "Extrayendo resultados de $($leagueDefinition.name)..."
    Write-Host "Log de extraccion: $logPath"
    $startedAt = Get-Date
    $scraperCommand = "`"$python`" `"$scraper`" --no-headless competition results `"$($leagueDefinition.resultsUrl)`" --output `"$output`" 2>&1"
    & cmd.exe /d /c $scraperCommand | Tee-Object -FilePath $logPath
    $scraperExitCode = $LASTEXITCODE
    if ($scraperExitCode -ne 0) { throw "El scraper termino con codigo $scraperExitCode." }

    $csv = Get-ChildItem -LiteralPath $competitionRoot -File | Where-Object { $_.Name -match $existingPattern -and $_.LastWriteTime -ge $startedAt } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $csv) { throw "No se encontro el RESULTS generado para $($leagueDefinition.code)." }
}

Write-Host "CSV generado: $($csv.FullName)"
if ($FromDate -or $ToDate) {
    if (-not $FromDate -or -not $ToDate) {
        throw 'Debes indicar FromDate y ToDate juntos para filtrar una jornada.'
    }
    if ($FromDate.Date -gt $ToDate.Date) {
        throw 'FromDate no puede ser posterior a ToDate.'
    }

    $filteredRows = @(Import-Csv -LiteralPath $csv.FullName | Where-Object {
        if ([string]::IsNullOrWhiteSpace($_.eventDatetime)) { return $false }
        $eventDate = [datetimeoffset]::Parse($_.eventDatetime).Date
        $eventDate -ge $FromDate.Date -and $eventDate -le $ToDate.Date
    })
    if ($filteredRows.Count -eq 0) {
        throw "No se encontraron resultados entre $($FromDate.ToString('yyyy-MM-dd')) y $($ToDate.ToString('yyyy-MM-dd'))."
    }

    $filteredPath = Join-Path $competitionRoot ("RESULTS_{0}_{1}_{2}.csv" -f (Get-Date -Format 'yyyyMMddHHmmss'), $leagueDefinition.country, $leagueDefinition.competition)
    $filteredRows | Export-Csv -LiteralPath $filteredPath -NoTypeInformation -Encoding UTF8
    $csv = Get-Item -LiteralPath $filteredPath
    Write-Host "CSV filtrado: $($csv.FullName) ($($filteredRows.Count) partidos)"
} else {
    $latestRows = Get-LatestMatchdayRows @(Import-Csv -LiteralPath $csv.FullName)
    $latestPath = Join-Path $competitionRoot ("RESULTS_{0}_{1}_{2}.csv" -f (Get-Date -Format 'yyyyMMddHHmmss'), $leagueDefinition.country, $leagueDefinition.competition)
    $latestRows | Export-Csv -LiteralPath $latestPath -NoTypeInformation -Encoding UTF8
    $csv = Get-Item -LiteralPath $latestPath
    Write-Host "Ultima jornada preparada: $($csv.FullName) ($(@($latestRows).Count) partidos)"
}
if ($SkipImport) {
    return [pscustomobject]@{
        League = $leagueDefinition.code
        Country = $leagueDefinition.country
        Competition = $leagueDefinition.competition
        CsvPath = $csv.FullName
        MarkerPath = $markerPath
        GeneratedOn = $today
        AlreadyProcessed = $false
    }
}
& (Join-Path $desktopRoot 'scripts\importar\IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1') -CsvPath $csv.FullName -Country $leagueDefinition.country -Competition $leagueDefinition.competition
if ($LASTEXITCODE -ne 0) { throw "La importacion termino con codigo $LASTEXITCODE." }
if (-not $FromDate) {
    @{ generatedOn = $today; csvPath = $csv.FullName; league = $leagueDefinition.code } |
        ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
}
Write-Host "Completado: $($leagueDefinition.name)" -ForegroundColor Green
