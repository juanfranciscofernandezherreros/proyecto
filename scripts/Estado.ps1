<#
.SYNOPSIS
  Estado del sistema en una sola pantalla (solo lectura).

.DESCRIPTION
  Resume en unas 30 lineas lo que de otro modo exige media docena de comandos:
  contenedores, servicios, ultimas cargas del launcher, hasta donde llegan los
  resultados de cada liga y cuantos partidos hay pendientes.

  No arranca, no para y no modifica nada. Lanzador: 1_EJECUTAR\ESTADO.bat.
  Codigo de salida: 0 si todo lo esencial responde, 1 si falta algo.
#>
[CmdletBinding()]
param(
    [string]$WebUrl = 'http://localhost:8083',
    [int]$Cargas = 5
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'config.ps1')
$problemas = [System.Collections.Generic.List[string]]::new()

function Http([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
        return [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Sql([string]$Query) {
    $out = $Query | & docker exec -i $Config.POSTGRES_CONTAINER psql -U $Config.DB_USER -d $Config.DB_NAME -X -q -t -A -F '|' 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($out | Where-Object { "$_".Trim() })
}

# ---------- 1. Contenedores ----------
Write-Host '== CONTENEDORES =='
$nombres = @(& docker ps --format '{{.Names}}' 2>$null)
if ($LASTEXITCODE -ne 0) {
    Write-Host '  Docker no responde (Docker Desktop parado).'
    exit 1
}
$esperados = [ordered]@{
    'postgres'  = 'postgres'
    'mongo'     = 'mongo'
    'projector' = 'projector'
    'api'       = 'match-api'
    'web'       = 'match-web'
    'grafana'   = 'grafana'
}
$linea = foreach ($clave in $esperados.Keys) {
    $arriba = [bool]($nombres | Where-Object { $_ -like "*$($esperados[$clave])*" })
    if (-not $arriba -and $clave -ne 'grafana') { $problemas.Add("contenedor $clave parado") }
    '{0}={1}' -f $clave, $(if ($arriba) { 'OK' } else { 'PARADO' })
}
Write-Host ('  ' + ($linea -join '  '))

# ---------- 2. Servicios ----------
# 0 = no escucha nadie. El launcher puede devolver 404 en esta ruta estando levantado.
Write-Host '== SERVICIOS (codigo HTTP; 0 = caido) =='
$servicios = [ordered]@{
    'web'       = "$WebUrl/"
    'api'       = "$($Config.API_URL)/actuator/health"
    'launcher'  = "$($Config.LAUNCHER_URL)/actuator/health"
    'auditoria' = "$($Config.AUDIT_URL)/latest"
}
$linea = foreach ($clave in $servicios.Keys) {
    $codigo = Http $servicios[$clave]
    if ($codigo -eq 0) { $problemas.Add("servicio $clave no responde") }
    '{0}={1}' -f $clave, $codigo
}
Write-Host ('  ' + ($linea -join '  '))

# ---------- 3. Ultimas cargas del launcher ----------
Write-Host "== ULTIMAS $Cargas CARGAS DEL LAUNCHER =="
$filas = Sql "SELECT to_char(created_at, 'MM-DD HH24:MI'), batch_type, status, coalesce(exit_code::text, '-') FROM public.batch_launch_request ORDER BY created_at DESC LIMIT $Cargas;"
if ($null -eq $filas) {
    Write-Host '  Postgres no responde.'
    $problemas.Add('postgres no responde')
} else {
    foreach ($f in $filas) {
        $c = "$f".Split('|')
        Write-Host ('  {0}  {1,-16} {2,-10} exit={3}' -f $c[0], $c[1], $c[2], $c[3])
    }
    $malas = Sql "SELECT count(*) FROM (SELECT status, exit_code FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 50) u WHERE status <> 'COMPLETED' OR coalesce(exit_code, 0) <> 0;"
    if ($malas -and [int]$malas[0] -gt 0) { Write-Host "  De las ultimas 50, $($malas[0]) no terminaron bien." }
}

# ---------- 4. Resultados por liga ----------
Write-Host '== RESULTADOS POR LIGA (ultimo | partidos | jugados sin resultado) =='
$filas = Sql @"
SELECT r.country || '/' || r.competition, to_char(max(r.event_datetime), 'YYYY-MM-DD'), count(*),
       (SELECT count(*) FROM fixtures.fixtures f
         WHERE f.country = r.country AND f.competition = r.competition
           AND f.event_datetime < now() AND f.event_datetime > max(r.event_datetime))
FROM results.results r
WHERE r.country <> '' AND r.competition <> ''
GROUP BY r.country, r.competition
ORDER BY 1;
"@
if ($null -ne $filas) {
    foreach ($f in $filas) {
        $c = "$f".Split('|')
        $aviso = if ([int]$c[3] -gt 0) { '  <-- atrasada' } else { '' }
        Write-Host ('  {0,-26} {1}  {2,4}  {3,3}{4}' -f $c[0], $c[1], $c[2], $c[3], $aviso)
        if ([int]$c[3] -gt 0) { $problemas.Add("$($c[0]): $($c[3]) partidos jugados sin resultado") }
    }
}

# ---------- 5. Pendientes de detalle ----------
Write-Host '== PENDIENTES DE DETALLE (auditoria) =='
try {
    $a = Invoke-RestMethod -Uri "$($Config.AUDIT_URL)/latest" -TimeoutSec 20
    Write-Host ('  fixtures={0}  elegibles={1}  pendientes={2}  (auditoria del {3})' -f `
        $a.totalFixtures, $a.eligibleFixtures, $a.pendingFixtures, "$($a.refreshedAt)".Substring(0, 16))
} catch {
    Write-Host '  La auditoria no responde.'
}

# ---------- Resumen ----------
Write-Host '== RESUMEN =='
if ($problemas.Count -eq 0) {
    Write-Host '  Todo lo esencial responde y ninguna liga va atrasada.'
    exit 0
}
foreach ($p in $problemas) { Write-Host "  - $p" }
exit 1
