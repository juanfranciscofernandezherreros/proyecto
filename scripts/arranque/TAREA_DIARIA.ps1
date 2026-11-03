param(
    [Parameter(Mandatory)][ValidateSet('instalar', 'quitar', 'estado', 'ejecutar')][string]$Accion,
    # Hora local a la que se lanza el ciclo (HH:mm).
    [ValidatePattern('^\d{2}:\d{2}$')][string]$Hora = '06:00'
)

$ErrorActionPreference = 'Stop'
$task = 'Basketball - Ciclo diario'
$script = (Resolve-Path (Join-Path $PSScriptRoot '..\..\1_EJECUTAR\CICLO_DIARIO.bat')).Path

switch ($Accion) {
    'instalar' {
        $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c start "Basketball ciclo diario" /min "{0}"' -f $script) `
            -WorkingDirectory (Split-Path $script -Parent)
        $trigger = New-ScheduledTaskTrigger -Daily -At $Hora
        # StartWhenAvailable: si el equipo estaba apagado a esa hora, se lanza en cuanto pueda.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable -WakeToRun
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force `
            -Description 'Cada dia extrae los RESULTS de todas las ligas y procesa los partidos pendientes de Basketball.' | Out-Null
        Write-Host "Tarea '$task' instalada: cada dia a las $Hora." -ForegroundColor Green
    }
    'quitar' {
        if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $task -Confirm:$false
            Write-Host 'Tarea quitada.'
        } else {
            Write-Host 'La tarea no estaba instalada.'
        }
    }
    'estado' {
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if (-not $t) { Write-Host 'Tarea no instalada.'; break }
        $info = $t | Get-ScheduledTaskInfo
        Write-Host ('Tarea: {0}' -f $t.TaskName)
        Write-Host ('Estado: {0} | Ultima ejecucion: {1} | Resultado: {2} | Proxima: {3}' -f $t.State, $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime)
    }
    'ejecutar' {
        Start-ScheduledTask -TaskName $task
        Write-Host "Tarea '$task' lanzada ahora."
    }
}
