# Recolector de consumo para el dashboard "Basketball - Consumo" (Grafana, uid consumo-recursos).
# Cada pocos segundos guarda en el esquema monitoring de PostgreSQL:
#   - CPU y RAM de cada componente (launcher, auditoria, batches, scraper, Edge, Docker...)
#     y de los contenedores de Docker;
#   - el heap de las JVM, leido con jcmd GC.heap_info;
#   - cada pocos minutos, el tamano de las carpetas temporales y de datos y el de la base.
# Las tablas y las consultas estan documentadas en sql\consultas\2026-11-03_1200_*.sql y
# sql\consultas\2026-11-03_1210_*.sql. Lo arranca "ASEGURAR.bat consumo" en segundo plano.
#
# Uso: RECOLECTAR_CONSUMO.ps1 [-IntervaloSegundos 15] [-UnaVez]
param(
    [int]$IntervaloSegundos = 15,
    # Toma una sola muestra (incluidas disco y base) y termina; sirve para probar.
    [switch]$UnaVez
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\config.ps1')
$workspace = $Config.WORKSPACE
$postgres = $Config.POSTGRES_CONTAINER
$jcmd = Join-Path (Split-Path $Config.JAVA_EXE -Parent) 'jcmd.exe'
$logDir = Join-Path $Config.REPORTS_DIR 'consumo'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'recolector-consumo.log'
$schemaFile = Join-Path $workspace 'sql\consultas\2026-11-03_1200_esquema-monitoring-consumo.sql'

$cores = [Environment]::ProcessorCount
$diskEvery = [TimeSpan]::FromMinutes(10)
$dbEvery = [TimeSpan]::FromMinutes(5)
$purgeEvery = [TimeSpan]::FromHours(1)
$retentionDays = 7

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $logFile -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message) -Encoding UTF8
}

# Igual que en ASEGURAR_SERVICIOS: con Stop, cualquier linea en stderr seria una excepcion.
function Invoke-Psql([string]$Sql) {
    $ErrorActionPreference = 'Continue'
    $out = $Sql | & docker exec -i $postgres psql -U $Config.DB_USER -d $Config.DB_NAME -q -v ON_ERROR_STOP=1 2>&1
    if ($LASTEXITCODE -ne 0) { throw "psql fallo: $($out -join ' ')" }
}

function Sql([object]$Value) {
    if ($null -eq $Value) { return 'NULL' }
    if ($Value -is [string]) { return "'" + $Value.Replace("'", "''") + "'" }
    return ([double]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)
}

# A que componente del proyecto pertenece un proceso. $null = no interesa.
function Get-Component($Process) {
    $name = $Process.Name.ToLowerInvariant()
    $cmd = "$($Process.CommandLine)"
    switch -Regex ($name) {
        '^javaw?\.exe$' {
            if ($cmd -like '*csv-batch-launcher.jar*') { return 'launcher' }
            if ($cmd -like '*fixtures-processing-audit.jar*') { return 'auditoria' }
            if ($cmd -match '(csv-[\w-]+-batch)\.jar') { return "batch:$($Matches[1])" }
            if ($cmd -like '*pronostico*') { return 'pronostico' }
            return 'java-otro'
        }
        '^pythonw?\.exe$' { if ($cmd -like "*$($Config.SCRAPER_DIR)*" -or $cmd -like '*flashscore*') { return 'scraper' }; return $null }
        '^msedgedriver\.exe$' { return 'edgedriver' }
        '^chromedriver\.exe$' { return 'chromedriver' }
        '^msedge\.exe$' { if ($cmd -like '*scoped_dir*' -or $cmd -like '*--remote-debugging*') { return 'edge-selenium' }; return 'edge-usuario' }
        '^chrome\.exe$' { if ($cmd -like '*scoped_dir*' -or $cmd -like '*--remote-debugging*') { return 'chrome-selenium' }; return $null }
        '^(vmmem|vmmemwsl|com\.docker\.backend|docker desktop)\.exe$|^vmmem' { return 'docker-vm' }
        '^powershell\.exe$|^pwsh\.exe$|^cmd\.exe$' { if ($cmd -like "*$workspace*") { return 'scripts' }; return $null }
    }
    return $null
}

$previousCpu = @{}
$previousAt = $null

function Get-ProcessRows([datetime]$Now) {
    $cpuNow = @{}
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try { $cpuNow[$p.Id] = $p.TotalProcessorTime.TotalSeconds } catch { }
    }
    $elapsed = if ($script:previousAt) { ($Now - $script:previousAt).TotalSeconds } else { $null }

    $groups = @{}
    foreach ($p in Get-CimInstance Win32_Process -Property ProcessId, Name, CommandLine, WorkingSetSize, ThreadCount) {
        $component = Get-Component $p
        if (-not $component) { continue }
        if (-not $groups.ContainsKey($component)) { $groups[$component] = @{ Name = $p.Name; Pids = @(); Cpu = 0.0; HasCpu = $false; Mem = 0.0; Threads = 0 } }
        $g = $groups[$component]
        $g.Pids += [int]$p.ProcessId
        $g.Mem += $p.WorkingSetSize / 1MB
        $g.Threads += [int]$p.ThreadCount
        $pidKey = [int]$p.ProcessId
        if ($elapsed -and $cpuNow.ContainsKey($pidKey) -and $script:previousCpu.ContainsKey($pidKey)) {
            $g.Cpu += [math]::Max(0, $cpuNow[$pidKey] - $script:previousCpu[$pidKey]) / $elapsed / $cores * 100
            $g.HasCpu = $true
        }
    }
    $script:previousCpu = $cpuNow
    $script:previousAt = $Now

    foreach ($component in $groups.Keys) {
        $g = $groups[$component]
        $singlePid = if ($g.Pids.Count -eq 1) { $g.Pids[0] } else { $null }
        [pscustomobject]@{ Component = $component; Name = $g.Name; Pid = $singlePid
                           Cpu = $(if ($g.HasCpu) { $g.Cpu } else { $null }); Mem = $g.Mem; Threads = $g.Threads }
    }
}

# docker stats da el CPU en % de un nucleo; se divide entre los nucleos para que sea
# comparable con los procesos de Windows (aproximado: la VM de Docker puede tener menos).
function Get-ContainerRows {
    $ErrorActionPreference = 'Continue'
    $lines = & docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    foreach ($line in $lines) {
        $name, $cpu, $mem = "$line".Split('|')
        if (-not $mem) { continue }
        $used = ($mem -split '/')[0].Trim()
        if ($used -notmatch '^([\d.]+)\s*([KMGT]?i?B)$') { continue }
        $factor = @{ 'B' = 1 / 1MB; 'KiB' = 1 / 1KB; 'MiB' = 1; 'GiB' = 1KB; 'TiB' = 1MB; 'kB' = 1 / 1KB; 'MB' = 1; 'GB' = 1KB }[$Matches[2]]
        $memMb = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) * $factor
        $cpuPct = [double]::Parse($cpu.TrimEnd('%'), [Globalization.CultureInfo]::InvariantCulture) / $cores
        [pscustomobject]@{ Component = "contenedor:$name"; Name = 'docker'; Pid = $null; Cpu = $cpuPct; Mem = $memMb; Threads = $null }
    }
}

# Heap de las JVM del proyecto. jcmd GC.heap_info (G1): "garbage-first heap   total 262144K, used 12345K".
function Get-JvmRows {
    if (-not (Test-Path -LiteralPath $jcmd)) { return }
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -Property ProcessId, Name, CommandLine) {
        $component = Get-Component $p
        $ErrorActionPreference = 'Continue'
        $info = & $jcmd $p.ProcessId GC.heap_info 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $line = $info | Where-Object { $_ -match 'heap\s+total\s+(\d+)K,\s+used\s+(\d+)K' } | Select-Object -First 1
        if (-not $line) { continue }
        $null = $line -match 'total\s+(\d+)K,\s+used\s+(\d+)K'
        [pscustomobject]@{ Component = $component; Pid = [int]$p.ProcessId; Used = [double]$Matches[2] / 1KB; Committed = [double]$Matches[1] / 1KB }
    }
}

function Measure-Folder([string[]]$Paths) {
    $files = @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Force -ErrorAction SilentlyContinue })
    [pscustomobject]@{ Mb = (($files | Measure-Object Length -Sum).Sum / 1MB); Files = $files.Count }
}

function Get-DiskRows {
    $temp = $env:TEMP
    $scoped = @(Get-ChildItem -LiteralPath $temp -Directory -Force -Filter 'scoped_dir*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $targets = @(Get-ChildItem -LiteralPath $workspace -Recurse -Directory -Force -Filter 'target' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|\.venv)\\' -and (Test-Path (Join-Path $_.Parent.FullName 'pom.xml')) } | ForEach-Object FullName)
    $dockerDisks = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Docker\wsl') -Recurse -File -Filter '*.vhdx' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $set = [ordered]@{
        'temp'        = @{ Path = $temp; Paths = @($temp) }
        'scoped_dir'  = @{ Path = "$temp\scoped_dir*"; Paths = $scoped }
        'maven-target'= @{ Path = "$workspace\**\target"; Paths = $targets }
        'reports'     = @{ Path = $Config.REPORTS_DIR; Paths = @($Config.REPORTS_DIR) }
        'datos'       = @{ Path = $Config.DATA_DIR; Paths = @($Config.DATA_DIR) }
        'ready'       = @{ Path = $Config.READY_ROOT; Paths = @($Config.READY_ROOT) }
    }
    foreach ($label in $set.Keys) {
        $m = Measure-Folder $set[$label].Paths
        [pscustomobject]@{ Label = $label; Path = $set[$label].Path; Mb = $m.Mb; Files = $m.Files }
    }
    if ($dockerDisks.Count) {
        $mb = ($dockerDisks | ForEach-Object { (Get-Item -LiteralPath $_ -Force).Length } | Measure-Object -Sum).Sum / 1MB
        [pscustomobject]@{ Label = 'docker-vhdx'; Path = "$env:LOCALAPPDATA\Docker\wsl\*.vhdx"; Mb = $mb; Files = $dockerDisks.Count }
    }
}

$dbSizeSql = @'
INSERT INTO monitoring.db_size_sample (sampled_at, schema_name, size_mb)
SELECT now(), '(total)', pg_database_size(current_database()) / 1048576.0
UNION ALL
SELECT now(), n.nspname, sum(pg_total_relation_size(c.oid)) / 1048576.0
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%'
GROUP BY n.nspname;
'@

$purgeSql = @"
DELETE FROM monitoring.process_sample WHERE sampled_at < now() - interval '$retentionDays days';
DELETE FROM monitoring.jvm_sample     WHERE sampled_at < now() - interval '$retentionDays days';
DELETE FROM monitoring.disk_sample    WHERE sampled_at < now() - interval '$retentionDays days';
DELETE FROM monitoring.db_size_sample WHERE sampled_at < now() - interval '$retentionDays days';
"@

Write-Log "arrancando (intervalo ${IntervaloSegundos}s, pid $PID)"
Invoke-Psql (Get-Content -Raw -Encoding UTF8 -LiteralPath $schemaFile)
$lastDisk = [datetime]::MinValue; $lastDb = [datetime]::MinValue; $lastPurge = [datetime]::MinValue

# La CPU se calcula por diferencia entre dos muestras: la primera solo deja la referencia.
$null = Get-ProcessRows (Get-Date)
Start-Sleep -Seconds $(if ($UnaVez) { 3 } else { $IntervaloSegundos })

while ($true) {
    try {
        $now = Get-Date
        $ts = Sql ($now.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz'))
        $sql = [Text.StringBuilder]::new()
        $rows = @(Get-ProcessRows $now) + @(Get-ContainerRows)
        foreach ($r in $rows) {
            [void]$sql.AppendLine("INSERT INTO monitoring.process_sample VALUES ($ts, $(Sql $r.Component), $(Sql $r.Name), $(Sql $r.Pid), $(Sql $r.Cpu), $(Sql $r.Mem), $(Sql $r.Threads));")
        }
        foreach ($j in Get-JvmRows) {
            [void]$sql.AppendLine("INSERT INTO monitoring.jvm_sample VALUES ($ts, $(Sql $j.Component), $(Sql $j.Pid), $(Sql $j.Used), $(Sql $j.Committed));")
        }
        if ($UnaVez -or ($now - $lastDisk) -ge $diskEvery) {
            foreach ($d in Get-DiskRows) {
                [void]$sql.AppendLine("INSERT INTO monitoring.disk_sample VALUES ($ts, $(Sql $d.Label), $(Sql $d.Path), $(Sql $d.Mb), $(Sql $d.Files));")
            }
            $lastDisk = $now
        }
        if ($UnaVez -or ($now - $lastDb) -ge $dbEvery) { [void]$sql.AppendLine($dbSizeSql); $lastDb = $now }
        if (($now - $lastPurge) -ge $purgeEvery) { [void]$sql.AppendLine($purgeSql); $lastPurge = $now }
        Invoke-Psql $sql.ToString()
    } catch {
        Write-Log "ERROR $($_.Exception.Message)"
    }
    if ($UnaVez) { break }
    Start-Sleep -Seconds $IntervaloSegundos
}
