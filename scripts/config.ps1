# Carga la configuracion unica del proyecto (config\basketball.env).
#
# Uso desde un .ps1:   . (Join-Path $PSScriptRoot '..\config.ps1')   (desde scripts\<carpeta>\)
#   Deja la configuracion en $Config (hashtable) y en variables de entorno, para que
#   tambien la reciban los procesos que se lancen despues. No define ninguna otra variable.
# Uso desde config.bat: config.ps1 -FormatoBat   (escribe CLAVE=valor, una por linea)
#
# Prioridad: variable de entorno > config\basketball.local.env > config\basketball.env.
param([switch]$FormatoBat)

function Get-BasketballConfig([string]$Workspace) {
    function Read-EnvFile([string]$Path) {
        $values = [ordered]@{}
        if (-not (Test-Path -LiteralPath $Path)) { return $values }
        foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) { continue }
            $key, $value = $trimmed.Split('=', 2)
            $values[$key.Trim()] = $value.Trim()
        }
        return $values
    }

    function Find-Jdk21 {
        $roots = 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft', 'C:\Program Files\Zulu'
        $jdks = foreach ($root in $roots) {
            Get-ChildItem -LiteralPath $root -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') }
        }
        # Version mas alta primero: se comparan los numeros rellenos con ceros (21.0.12 > 21.0.9).
        $jdks | Sort-Object -Descending {
            ([regex]::Matches(($_.Name -replace '^jdk-', '').Split('-')[0], '\d+') | ForEach-Object { $_.Value.PadLeft(6, '0') }) -join '.'
        } | Select-Object -First 1 -ExpandProperty FullName
    }

    $defaults = Read-EnvFile (Join-Path $Workspace 'config\basketball.env')
    $local = Read-EnvFile (Join-Path $Workspace 'config\basketball.local.env')
    $config = [ordered]@{ WORKSPACE = $Workspace; SCRIPTS = Join-Path $Workspace 'scripts' }
    foreach ($key in @($defaults.Keys) + @($local.Keys | Where-Object { -not $defaults.Contains($_) })) {
        $fromEnv = [Environment]::GetEnvironmentVariable($key)
        $value = if ($fromEnv) { $fromEnv } elseif ($local.Contains($key)) { $local[$key] } else { $defaults[$key] }
        # ${CLAVE} -> valor de una clave ya calculada.
        foreach ($m in [regex]::Matches([string]$value, '\$\{([A-Z0-9_]+)\}')) {
            $value = $value.Replace($m.Value, [string]$config[$m.Groups[1].Value])
        }
        $config[$key] = $value
    }
    if (-not $config.JAVA_HOME -or -not (Test-Path (Join-Path $config.JAVA_HOME 'bin\java.exe'))) {
        $config.JAVA_HOME = Find-Jdk21
    }
    $config.JAVA_EXE = if ($config.JAVA_HOME) { Join-Path $config.JAVA_HOME 'bin\java.exe' } else { '' }
    return $config
}

$Config = Get-BasketballConfig (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($FormatoBat) {
    $Config.Keys | ForEach-Object { "$_=$($Config[$_])" }
    return
}
$Config.Keys | ForEach-Object { [Environment]::SetEnvironmentVariable($_, [string]$Config[$_], 'Process') }
