# Deja en EDGEDRIVER_PATH el msedgedriver.exe de la misma version que el Edge instalado.
# Edge se actualiza solo y el driver debe coincidir con su version; si no coincide se
# descarga de la web oficial de Microsoft y solo se usa si esta firmado por Microsoft.
#
# Uso: ACTUALIZAR_EDGEDRIVER.ps1   (codigo 0 si el driver queda listo)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')

$driver = $Config.EDGEDRIVER_PATH
$edgeExe = @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
             'C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edgeExe) { Write-Host 'ERROR: Microsoft Edge no esta instalado.'; exit 1 }
$edgeVersion = (Get-Item $edgeExe).VersionInfo.ProductVersion

function Get-DriverVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    # Se lee de los metadatos del fichero: no hace falta ejecutarlo.
    return (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
}

$current = Get-DriverVersion $driver
if ($current -eq $edgeVersion) {
    Write-Host "msedgedriver $current ya coincide con Edge $edgeVersion"
    exit 0
}

Write-Host "Edge $edgeVersion y msedgedriver '$current' no coinciden: descargando el driver oficial..."
$work = Join-Path $env:TEMP "msedgedriver-$edgeVersion-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    $zip = Join-Path $work 'edgedriver_win64.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "https://msedgedriver.microsoft.com/$edgeVersion/edgedriver_win64.zip" -OutFile $zip -TimeoutSec 120
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
    $downloaded = Join-Path $work 'msedgedriver.exe'
    $signature = Get-AuthenticodeSignature $downloaded
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "el driver descargado no esta firmado por Microsoft ($($signature.Status))"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $driver -Parent) | Out-Null
    Copy-Item -LiteralPath $downloaded -Destination $driver -Force
    Write-Host "msedgedriver actualizado a $(Get-DriverVersion $driver) en $driver"
    exit 0
} catch {
    Write-Host "ERROR: no se pudo actualizar msedgedriver: $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
