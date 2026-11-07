<#
.SYNOPSIS
  Verificacion ejecutable del sistema, ligada al SDD y al documento de verificacion.
  Convierte las comprobaciones de docs/VERIFICACION-SDD.md en checks verde/rojo.

.DESCRIPTION
  Requiere el stack arrancado (ARRANCAR_TODO.bat). Devuelve codigo 0 si todo pasa,
  1 si algo falla. Pensado para lanzarlo a mano o desde un hook/CI.

  Comprobaciones:
    1. Web (8083) y API (8082) responden 200.
    2. results y fixtures no tienen slugs de competicion no canonicos (acb/super-league).
    3. /api/v1/matches/filters no ofrece acb ni super-league.
    4. Un partido de spain/liga-endesa une fixture + result con la misma competicion.
#>
[CmdletBinding()]
param(
    [string]$WebUrl = 'http://localhost:8083',
    [string]$ApiUrl = 'http://localhost:8082',
    [string]$PostgresContainer = 'local-validation-postgres-1',
    [string]$MongoContainer = 'local-validation-mongo-1'
)

$ErrorActionPreference = 'Stop'
$fail = 0
function Ok($m)   { Write-Host "  OK   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }

function Psql([string]$sql) {
    return (& docker exec -i $PostgresContainer psql -U test -d basketball -tAc $sql 2>&1).Trim()
}
function Mongo([string]$js) {
    return (& docker exec -i $MongoContainer mongosh --quiet basketball --eval $js 2>&1 | Select-Object -Last 1).Trim()
}
function HttpCode([string]$url) {
    try { return [int](Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}

Write-Host '== Verificacion del sistema (SDD) ==' -ForegroundColor Cyan

# 1. Web y API
if ((HttpCode "$WebUrl/") -eq 200) { Ok 'Web responde 200' } else { Bad 'Web no responde 200' }
if ((HttpCode "$ApiUrl/actuator/health") -eq 200) { Ok 'API responde 200' } else { Bad 'API no responde 200' }

# 2. Sin slugs no canonicos en PG
$nf = Psql "SELECT count(*) FROM fixtures.fixtures WHERE competition IN ('acb','super-league');"
$nr = Psql "SELECT count(*) FROM results.results  WHERE competition IN ('acb','super-league');"
if ($nf -eq '0') { Ok 'fixtures sin slug no canonico' } else { Bad "fixtures con slug no canonico: $nf" }
if ($nr -eq '0') { Ok 'results sin slug no canonico'  } else { Bad "results con slug no canonico: $nr" }

# 3. Filtros de la API sin acb/super-league
try {
    $filters = Invoke-RestMethod -UseBasicParsing -Uri "$ApiUrl/api/v1/matches/filters" -TimeoutSec 5
    $comps = @($filters.competitions)
    if ($comps -notcontains 'acb' -and $comps -notcontains 'super-league') { Ok '/filters sin acb/super-league' }
    else { Bad "/filters aun ofrece: $([string]::Join(',', ($comps | Where-Object { $_ -in 'acb','super-league' })))" }
} catch { Bad "no se pudo leer /filters: $($_.Exception.Message)" }

# 4. Join fixture+result en spain/liga-endesa
try {
    $r = Invoke-RestMethod -UseBasicParsing -Uri "$ApiUrl/api/v1/matches?page=0&size=1&country=spain&competition=liga-endesa&status=finished" -TimeoutSec 5
    $m = @($r.content)[0]
    if ($m -and $m.fixture.competition -eq 'liga-endesa' -and $m.result.competition -eq 'liga-endesa') {
        Ok "partido spain une fixture+result ($($m.matchId))"
    } else { Bad 'no hay partido spain/liga-endesa consistente' }
} catch { Bad "no se pudo verificar el join: $($_.Exception.Message)" }

# 5. Projector: no hay documentos con seccion fixture pero sin objeto fixture
$rotos = Mongo 'print(db.matches.countDocuments({availableSections:/^fixture$/, fixture:null}))'
if ($rotos -eq '0') { Ok 'Mongo: ningun partido con fixture nula' } else { Bad "Mongo: $rotos partidos con availableSections=fixture pero objeto fixture nulo" }

Write-Host ''
if ($fail -eq 0) { Write-Host 'RESULTADO: VERDE (todas las comprobaciones pasan)' -ForegroundColor Green; exit 0 }
else { Write-Host "RESULTADO: ROJO ($fail comprobacion(es) fallida(s))" -ForegroundColor Red; exit 1 }
