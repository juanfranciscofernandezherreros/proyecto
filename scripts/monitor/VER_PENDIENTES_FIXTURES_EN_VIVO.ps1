$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\config.ps1')
$uri = "$($Config.AUDIT_URL)/latest"

while ($true) {
    try {
        $snapshot = Invoke-RestMethod -Uri $uri -TimeoutSec 8
        Clear-Host
        Write-Host 'PENDIENTES DE PROCESAR - AUDITORIA DE FIXTURES' -ForegroundColor Cyan
        Write-Host ("Actualizado: {0} | Estado: {1} | Pendientes: {2}" -f $snapshot.refreshedAt, $snapshot.status, $snapshot.pendingFixtures) -ForegroundColor Yellow
        Write-Host 'La lista se refresca desde PostgreSQL cada 5 segundos. Cierra con Ctrl+C.' -ForegroundColor DarkGray
        if ($snapshot.status -ne 'COMPLETED') {
            Write-Host ("Error de auditoria: {0}" -f $snapshot.error) -ForegroundColor Red
        } elseif (-not $snapshot.pendingMatches -or $snapshot.pendingMatches.Count -eq 0) {
            Write-Host 'No quedan partidos pendientes.' -ForegroundColor Green
        } else {
            $snapshot.pendingMatches |
                Select-Object matchDate, country, competition, matchId, homeTeam, awayTeam,
                    @{Name='datasets_faltantes'; Expression={ $_.pendingDatasets -join ',' }} |
                Format-Table -AutoSize |
                Out-String -Width 240 |
                Write-Host
        }
    } catch {
        Clear-Host
        Write-Host 'PENDIENTES DE PROCESAR - AUDITORIA DE FIXTURES' -ForegroundColor Cyan
        Write-Host ("Esperando endpoint {0}: {1}" -f $uri, $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Seconds 5
}
