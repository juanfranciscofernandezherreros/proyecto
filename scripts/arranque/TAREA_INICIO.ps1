param(
    [Parameter(Mandatory)][ValidateSet('instalar', 'quitar', 'estado', 'ejecutar')][string]$Accion,
    # Espera tras iniciar sesion para que red y Docker Desktop tengan tiempo de despertar.
    [ValidateRange(0, 60)][int]$RetrasoMinutos = 2
)

$ErrorActionPreference = 'Stop'
$task = 'Basketball - Procesamiento automatico al iniciar'
$script = (Resolve-Path (Join-Path $PSScriptRoot '..\..\1_EJECUTAR\AUTOMATICO_INICIO.bat')).Path

switch ($Accion) {
    'instalar' {
        $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c start "Basketball automatico" /min "{0}"' -f $script) `
            -WorkingDirectory (Split-Path $script -Parent)
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        if ($RetrasoMinutos -gt 0) { $trigger.Delay = 'PT{0}M' -f $RetrasoMinutos }
        # Sin limite de tiempo: procesar todos los pendientes puede llevar horas.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force `
            -Description 'Al iniciar sesion arranca Docker y los servicios de Basketball si estan parados y procesa los partidos pendientes.' | Out-Null
        Write-Host "Tarea '$task' instalada: se ejecuta al iniciar sesion ($RetrasoMinutos min de espera)." -ForegroundColor Green
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
        Write-Host ('Estado: {0} | Ultima ejecucion: {1} | Resultado: {2}' -f $t.State, $info.LastRunTime, $info.LastTaskResult)
        Write-Host ('Disparador: al iniciar sesion {0}, espera {1}' -f $t.Triggers[0].UserId, $t.Triggers[0].Delay)
    }
    'ejecutar' {
        Start-ScheduledTask -TaskName $task
        Write-Host "Tarea '$task' lanzada ahora."
    }
}
