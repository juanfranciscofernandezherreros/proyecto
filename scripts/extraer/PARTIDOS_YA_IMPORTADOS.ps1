param(
    [Parameter(Mandatory)][ValidateSet('MATCH_SUMMARY', 'TEAM_STATS', 'PLAYER_STATS', 'POINT_BY_POINT')][string]$Dataset,
    # Si se indica, escribe un match_id por linea en este fichero (para los .bat).
    [string]$Salida
)

# Devuelve los match_id que ya tienen filas del dataset en PostgreSQL. Los extractores los
# saltan para no volver a abrir Flashscore ni generar otro CSV de un partido ya importado.
# Son las mismas tablas que mira la auditoria de pendientes (fixtures-processing-audit).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$tables = @{
    MATCH_SUMMARY = 'match_summary.match_summary'
    TEAM_STATS = 'team_stats.team_stats'
    PLAYER_STATS = 'stats_player.stats_player'
    POINT_BY_POINT = 'point_by_point.point_by_point_event'
}
$composeFile = Join-Path $Config.WORKSPACE 'local-validation\docker-compose.yml'
$ids = @(& docker compose -f $composeFile exec -T postgres psql -U $Config.DB_USER -d $Config.DB_NAME --no-psqlrc -At `
    -c "SELECT DISTINCT match_id FROM $($tables[$Dataset]) WHERE match_id IS NOT NULL")
if ($LASTEXITCODE -ne 0) { throw "No se pudieron leer los partidos ya importados de $Dataset." }
$ids = @($ids | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Salida) {
    Set-Content -LiteralPath $Salida -Value $ids -Encoding ASCII
} else {
    $ids
}
