@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

set "ENDPOINT=%AUDIT_URL%/run"
set "LATEST=%AUDIT_URL%/latest"

echo Arrancando PostgreSQL y modulo persistente antes de consultar el endpoint...
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo watcher postgres auditoria
if errorlevel 1 exit /b %ERRORLEVEL%

echo Consultando auditoria de fixtures en %ENDPOINT%...
%PS% -Command ^
  "$ErrorActionPreference='Stop'; $s=Invoke-RestMethod -Method Post -Uri '%ENDPOINT%' -TimeoutSec 60; if ($s.status -ne 'COMPLETED') { throw ('Auditoria fallo: ' + $s.error) }; $reportDir='%REPORT_DIR%'; New-Item -ItemType Directory -Force -Path $reportDir | Out-Null; $pending=@($s.pendingMatches); $stamp=Get-Date -Format 'yyyyMMddHHmmss'; $output=Join-Path $reportDir ('FIXTURES_PROCESSING_AUDIT_PENDING_'+$stamp+'.csv'); $items=@($pending | Select-Object @{Name='match_date';Expression={$_.matchDate}},country,competition,@{Name='match_id';Expression={$_.matchId}},@{Name='home_team';Expression={$_.homeTeam}},@{Name='away_team';Expression={$_.awayTeam}},@{Name='pending_datasets';Expression={$_.pendingDatasets -join ','}}); if ($items.Count) { $items | Export-Csv -LiteralPath $output -NoTypeInformation -Encoding UTF8 } else { 'match_date,country,competition,match_id,home_team,away_team,pending_datasets' | Set-Content -LiteralPath $output -Encoding UTF8 }; Write-Host ('Corte: '+$s.cutoffDate+' | Fixtures: '+$s.totalFixtures+' | Elegibles: '+$s.eligibleFixtures+' | Pendientes: '+$s.pendingFixtures); if ($items.Count) { $items | Format-Table -AutoSize } else { Write-Host 'No quedan partidos pendientes.' -ForegroundColor Green }; Write-Host ('Lista CSV: '+$output); Write-Host ('JSON en vivo: %LATEST%')"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" echo ERROR: fallo la consulta a la auditoria.
exit /b %EXIT_CODE%
