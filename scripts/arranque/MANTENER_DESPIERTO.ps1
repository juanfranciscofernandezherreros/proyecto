# Impide que Windows suspenda el equipo o apague la pantalla mientras este proceso viva.
# Usa SetThreadExecutionState, la funcion oficial de Windows para esto (la misma que usan los
# reproductores de video): no simula teclado ni raton, por eso no alerta al antivirus.
# Al cerrar la ventana, Windows recupera su comportamiento normal de ahorro de energia.

Add-Type -Namespace Basketball -Name Energia -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

$ES_CONTINUOUS = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED = [uint32]'0x00000001'
$ES_DISPLAY_REQUIRED = [uint32]'0x00000002'
$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

Write-Host 'Antibloqueo activo: Windows no suspendera el equipo ni apagara la pantalla.'
Write-Host 'Cierra esta ventana para detenerlo.'
while ($true) {
    # Con ES_CONTINUOUS basta una llamada, pero se repite por si otro programa la anula.
    if ([Basketball.Energia]::SetThreadExecutionState($flags) -eq 0) {
        Write-Host 'AVISO: Windows rechazo la peticion de mantener el equipo despierto.'
    }
    Start-Sleep -Seconds 60
}
