# Impide que Windows suspenda el equipo, apague la pantalla o la bloquee por inactividad
# mientras este proceso viva.
# 1. SetThreadExecutionState: la funcion oficial de Windows para no suspender ni apagar la
#    pantalla (la misma que usan los reproductores de video).
# 2. SendInput con un movimiento de raton de 0 pixeles cada 50 s: el cursor no se mueve y no
#    se pulsa ninguna tecla, pero Windows lo cuenta como actividad y reinicia su contador de
#    inactividad, que es el que dispara el bloqueo de pantalla (salvapantallas con contrasena,
#    "bloquear tras X minutos" o directivas de inactividad). SetThreadExecutionState solo no
#    lo evita.
# Al cerrar la ventana, Windows recupera su comportamiento normal.

Add-Type -Namespace Basketball -Name Energia -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public System.IntPtr dwExtraInfo; }

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct INPUT { public uint type; public MOUSEINPUT mi; }

[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

// Movimiento relativo de 0 pixeles: reinicia el contador de inactividad sin mover el cursor.
public static bool Actividad() {
    var input = new INPUT[1];
    input[0].type = 0;            // INPUT_MOUSE
    input[0].mi.dwFlags = 0x0001; // MOUSEEVENTF_MOVE
    return SendInput(1, input, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT))) == 1;
}

// Segundos desde la ultima actividad (teclado o raton) que ve Windows.
public static uint SegundosInactivo() {
    var info = new LASTINPUTINFO();
    info.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
    GetLastInputInfo(ref info);
    return ((uint)System.Environment.TickCount - info.dwTime) / 1000;
}
'@

$ES_CONTINUOUS = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED = [uint32]'0x00000001'
$ES_DISPLAY_REQUIRED = [uint32]'0x00000002'
$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

Write-Host 'Antibloqueo activo: Windows no suspendera el equipo, ni apagara ni bloqueara la pantalla.'
Write-Host 'Cierra esta ventana para detenerlo.'
while ($true) {
    # Con ES_CONTINUOUS basta una llamada, pero se repite por si otro programa la anula.
    if ([Basketball.Energia]::SetThreadExecutionState($flags) -eq 0) {
        Write-Host 'AVISO: Windows rechazo la peticion de mantener el equipo despierto.'
    }
    if (-not [Basketball.Energia]::Actividad()) {
        Write-Host 'AVISO: Windows rechazo la senal de actividad (contador de inactividad).'
    }
    Start-Sleep -Seconds 50
}
