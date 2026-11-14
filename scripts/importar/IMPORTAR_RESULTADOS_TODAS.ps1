<#
.SYNOPSIS
  Procesa los CSV de RESULTS que ya estan en disco y los carga en PostgreSQL,
  sin volver a extraer nada de Flashscore.

.DESCRIPTION
  Para cada liga de LIGAS_BASKET.json busca en
  COMPETITIONS_DIR\<pais>\<competicion>\ los ficheros
  RESULTS_<fecha>_<pais>_<competicion>.csv y los importa con
  IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1 (launcher -> results.results).

  Por defecto importa solo el CSV mas reciente de cada liga: cada RESULTS es la
  pagina completa de resultados, asi que el ultimo contiene a los anteriores.
  Con -Todos importa todos los ficheros, del mas antiguo al mas reciente.

  Un fallo en una liga no detiene las demas. Lanzador: 1_EJECUTAR\PROCESAR_CSV_RESULTADOS.bat.
  Codigo de salida: 0 si no hubo fallos, 1 si alguno fallo.
#>
[CmdletBinding()]
param(
    [string]$League = 'ALL',
    [switch]$Todos
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$importador = Join-Path $PSScriptRoot 'IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1'

# Bucle explicito: Windows PowerShell 5.1 puede envolver el array del JSON en un solo elemento.
$ligas = [System.Collections.Generic.List[object]]::new()
foreach ($lg in (Get-Content -Raw -LiteralPath $Config.LEAGUE_CATALOG | ConvertFrom-Json)) { $ligas.Add($lg) }
$todas = ($League.Trim().ToUpperInvariant() -eq 'ALL')
$seleccion = [System.Collections.Generic.List[object]]::new()
foreach ($lg in $ligas) {
    if ($todas -or ("$($lg.code)".Trim() -eq $League.Trim())) { $seleccion.Add($lg) }
}
if ($seleccion.Count -eq 0) { throw "Liga no encontrada: $League" }

$resumen = [System.Collections.Generic.List[object]]::new()
foreach ($lg in $seleccion) {
    $carpeta = Join-Path $Config.COMPETITIONS_DIR "$($lg.country)\$($lg.competition)"
    $ficheros = @()
    if (Test-Path -LiteralPath $carpeta -PathType Container) {
        $ficheros = @(Get-ChildItem -LiteralPath $carpeta -File -Filter "RESULTS_*_$($lg.country)_$($lg.competition).csv" |
            Where-Object { $_.Name -match '^RESULTS_\d{14}_' } | Sort-Object Name)
    }
    if ($ficheros.Count -eq 0) {
        Write-Host "[OMITIDO] [$($lg.code)] no hay CSV de RESULTS en $carpeta" -ForegroundColor DarkYellow
        $resumen.Add([pscustomobject]@{ Liga = $lg.code; Fichero = '-'; Filas = 0; Estado = 'OMITIDO'; Detalle = 'sin CSV' })
        continue
    }
    if (-not $Todos) { $ficheros = @($ficheros[-1]) }

    foreach ($f in $ficheros) {
        Write-Host "PROCESAR [$($lg.code)] $($f.Name)" -ForegroundColor Cyan
        $filas = 0
        try {
            $filas = @(Import-Csv -LiteralPath $f.FullName).Count
            & $importador -CsvPath $f.FullName -Country $lg.country -Competition $lg.competition | Out-Null
            $resumen.Add([pscustomobject]@{ Liga = $lg.code; Fichero = $f.Name; Filas = $filas; Estado = 'OK'; Detalle = '' })
        } catch {
            $mensaje = $_.Exception.Message
            Write-Host "[FALLO] [$($lg.code)] $mensaje" -ForegroundColor Red
            $resumen.Add([pscustomobject]@{ Liga = $lg.code; Fichero = $f.Name; Filas = $filas; Estado = 'FALLO'; Detalle = $mensaje })
        }
    }
}

Write-Host ''
Write-Host '==================== RESUMEN ====================' -ForegroundColor Cyan
$resumen | Format-Table Liga, Fichero, Filas, Estado -AutoSize | Out-String -Width 200 | Write-Host
$fallos = @($resumen | Where-Object Estado -eq 'FALLO')
$ok = @($resumen | Where-Object Estado -eq 'OK').Count
$omitidos = @($resumen | Where-Object Estado -eq 'OMITIDO').Count
Write-Host ("CSV procesados: {0} OK, {1} con fallo, {2} ligas sin CSV." -f $ok, $fallos.Count, $omitidos)
if ($fallos.Count -eq 0) { exit 0 }
Write-Host 'Fallos:' -ForegroundColor Red
$fallos | ForEach-Object { Write-Host "  [$($_.Liga)] $($_.Fichero): $($_.Detalle)" -ForegroundColor Red }
exit 1
