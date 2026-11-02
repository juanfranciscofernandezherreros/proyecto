param(
    [Parameter(Mandatory)][ValidateSet('instalar', 'quitar', 'estado')][string]$Accion,
    [ValidateRange(1, 1440)][int]$Minutos = 5
)

$ErrorActionPreference = 'Stop'
$task = 'Basketball - Vigilar servicios'
$watchdog = (Resolve-Path (Join-Path $PSScriptRoot '..\..\1_EJECUTAR\VIGILAR_SERVICIOS.bat')).Path

switch ($Accion) {
    'instalar' {
        $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c start "Vigilante" /min "{0}" {1}' -f $watchdog, $Minutos)
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Force `
            -Description 'Comprueba cada pocos minutos los servicios de Basketball y arranca los que esten parados.' | Out-Null
        Start-ScheduledTask -TaskName $task
        Write-Host "Tarea '$task' instalada: al iniciar sesion vigila cada $Minutos min. Ya esta en marcha." -ForegroundColor Green
    }
    'quitar' {
        if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $task -Confirm:$false
            Write-Host 'Tarea quitada. La ventana del vigilante abierta sigue hasta que la cierres.'
        } else {
            Write-Host 'La tarea no estaba instalada.'
        }
    }
    'estado' {
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if (-not $t) { Write-Host 'Tarea no instalada.'; break }
        $info = $t | Get-ScheduledTaskInfo
        Write-Host ('Tarea: {0} | Estado: {1} | Ultima ejecucion: {2}' -f $t.TaskName, $t.State, $info.LastRunTime)
    }
}
