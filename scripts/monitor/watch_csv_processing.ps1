$ErrorActionPreference = 'Continue'
$container = 'local-validation-postgres-1'
$sql = @"
WITH active AS (
    SELECT request_id, batch_type, status, file_path, created_at, started_at, finished_at, error
    FROM public.batch_launch_request
    WHERE status IN ('QUEUED', 'RUNNING', 'BLOCKED')
), recent AS (
    SELECT request_id, batch_type, status, file_path, created_at, started_at, finished_at, error
    FROM public.batch_launch_request
    WHERE status IN ('COMPLETED', 'FAILED')
    ORDER BY finished_at DESC NULLS LAST
    LIMIT 15
), selected AS (
    SELECT *, 0 AS order_rank FROM active
    UNION ALL
    SELECT *, 1 AS order_rank FROM recent
)
SELECT COALESCE(json_agg(to_jsonb(selected) ORDER BY order_rank, created_at DESC), '[]'::json)::text
FROM selected;
"@

while ($true) {
    try {
        $json = & docker exec $container psql -U test -d basketball -X -A -t -c $sql 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar batch_launch_request en PostgreSQL.' }
        $items = @((($json -join '').Trim()) | ConvertFrom-Json)
        Clear-Host
        Write-Host 'IMPORTACIONES REALES DEL CSV BATCH LAUNCHER' -ForegroundColor Cyan
        Write-Host ("Actualizado: {0:HH:mm:ss} | En cola: {1} | Ejecutandose: {2} | Bloqueados: {3}" -f `
            (Get-Date), @($items | Where-Object status -eq 'QUEUED').Count,
            @($items | Where-Object status -eq 'RUNNING').Count,
            @($items | Where-Object status -eq 'BLOCKED').Count) -ForegroundColor Yellow
        Write-Host 'Se muestran solicitudes del launcher, no CSV meramente generados. Refresco cada 2 s. Ctrl+C para cerrar.' -ForegroundColor DarkGray
        if ($items.Count -eq 0) {
            Write-Host 'No hay importaciones en cola, en ejecucion o recientes.' -ForegroundColor Green
        } else {
            $items |
                Select-Object status, batch_type,
                    @{Name='csv'; Expression={ Split-Path -Leaf $_.file_path }},
                    @{Name='solicitado'; Expression={ $_.created_at }},
                    @{Name='inicio'; Expression={ $_.started_at }},
                    @{Name='fin'; Expression={ $_.finished_at }},
                    @{Name='detalle'; Expression={ $_.error }} |
                Format-Table -AutoSize |
                Out-String -Width 240 |
                Write-Host
        }
    } catch {
        Clear-Host
        Write-Host 'IMPORTACIONES REALES DEL CSV BATCH LAUNCHER' -ForegroundColor Cyan
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
