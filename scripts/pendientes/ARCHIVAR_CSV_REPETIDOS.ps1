param(
    # Sin -Aplicar solo muestra lo que moveria (no toca nada).
    [switch]$Aplicar
)

# Deja un unico CSV vigente por carpeta y dataset: el mas reciente. Los anteriores se mueven a
# una carpeta historico FUERA de las carpetas que vigila el launcher (que las recorre de forma
# recursiva y reimportaria lo que encontrase dentro):
#   READY_DIR (...\basketball-ready\current\<match_id>)  -> READY_ROOT\historico\current\<match_id>
#   COMPETITIONS_DIR (...\basketball\competitions\...)   -> DATA_DIR\historico\competitions\...
# El dataset se identifica por el nombre sin la marca de tiempo de 14 cifras, p. ej.
# PLAYER_STATS_20261102142353_04Lm2Xkm.csv -> PLAYER_STATS_*_04Lm2Xkm.csv. Los ficheros con el
# mismo nombre base y otra extension (p. ej. RESULTS_...coverage.json) se mueven con su CSV.
# No mueve un CSV que el launcher tenga en cola, en curso o bloqueado.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$roots = @(
    @{ Source = $Config.READY_DIR; Target = Join-Path $Config.READY_ROOT 'historico\current' },
    @{ Source = $Config.COMPETITIONS_DIR; Target = Join-Path $Config.DATA_DIR 'historico\competitions' }
)

$composeFile = Join-Path $Config.WORKSPACE 'local-validation\docker-compose.yml'
$busy = @(& docker compose -f $composeFile exec -T postgres psql -U $Config.DB_USER -d $Config.DB_NAME --no-psqlrc -At `
    -c "SELECT file_path FROM public.batch_launch_request WHERE status IN ('QUEUED','RUNNING','BLOCKED')")
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la cola del launcher; no se mueve nada.' }
$busySet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($busy | ForEach-Object { $_.Trim() } | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)

$moved = 0
$kept = 0
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root.Source -PathType Container)) { continue }
    $groups = Get-ChildItem -LiteralPath $root.Source -Recurse -File -Filter '*.csv' |
        Where-Object { $_.Name -match '_\d{14}_' } |
        Group-Object { Join-Path $_.DirectoryName ($_.Name -replace '_\d{14}_', '_*_') }
    foreach ($group in $groups) {
        $ordered = @($group.Group | Sort-Object LastWriteTime -Descending)
        $kept++
        foreach ($old in ($ordered | Select-Object -Skip 1)) {
            if ($busySet.Contains($old.FullName)) {
                Write-Host "[EN COLA] $($old.FullName) se deja: el launcher aun lo tiene pendiente." -ForegroundColor DarkYellow
                continue
            }
            $relative = $old.DirectoryName.Substring($root.Source.TrimEnd('\').Length).TrimStart('\')
            $targetDir = Join-Path $root.Target $relative
            $companions = @(Get-ChildItem -LiteralPath $old.DirectoryName -File -Filter "$($old.BaseName).*")
            foreach ($file in $companions) {
                if ($Aplicar) {
                    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                    Move-Item -LiteralPath $file.FullName -Destination (Join-Path $targetDir $file.Name) -Force
                } else {
                    Write-Host "[SIMULACION] $($file.FullName) -> $targetDir"
                }
                $moved++
            }
        }
    }
}
$verb = if ($Aplicar) { 'movidos' } else { 'se moverian' }
Write-Host "Datasets con fichero vigente: $kept. Ficheros antiguos $verb al historico: $moved." -ForegroundColor Green
if (-not $Aplicar -and $moved) { Write-Host 'Para moverlos de verdad: ARCHIVAR_CSV_REPETIDOS.bat aplicar' }
