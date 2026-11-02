# Unico punto de comprobacion y arranque de servicios.
# Para cada servicio pedido: comprueba si esta listo; si no, lo arranca y espera a que lo este.
# Las dependencias se resuelven solas (launcher -> postgres -> docker).
#
# Uso: ASEGURAR_SERVICIOS.ps1 -Servicios postgres,launcher [-ReiniciarLauncher] [-ActualizarDashboard]
# Servicios: antibloqueo, watcher, docker, postgres, runtime, auditoria, launcher, grafana
param(
    [Parameter(Mandatory)][string[]]$Servicios,
    [switch]$ReiniciarLauncher,
    # Reimporta el dashboard de pendientes aunque ya exista (pisa cambios hechos en la web).
    [switch]$ActualizarDashboard
)

$ErrorActionPreference = 'Stop'

function Get-Setting([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$batchRoot = Join-Path $workspace 'csv-extra-batch'
$reportDir = Get-Setting 'REPORT_DIR' 'C:\data\basketball\reports\orchestrator'
$javaExe = Get-Setting 'JAVA_EXE' 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe'
$dockerDesktop = Get-Setting 'DOCKER_DESKTOP' 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$composeFile = Get-Setting 'COMPOSE_FILE' (Join-Path $workspace 'local-validation\docker-compose.yml')
$auditUrl = Get-Setting 'AUDIT_URL' 'http://localhost:8090/fixtures-processing-audit'
$launcherUrl = (Get-Setting 'LAUNCHER_URL' 'http://localhost:8088/').TrimEnd('/') + '/'
$competitionsDir = Get-Setting 'COMPETITIONS_DIR' 'C:\data\basketball\competitions'
$readyDir = Get-Setting 'READY_DIR' 'C:\data\basketball-ready\current'
# Los importadores envian CSV de competitions\ y el pipeline por match_id de basketball-ready\;
# el launcher comun admite ambos para no tener que reiniciarlo segun quien lo use.
$launcherAllowedRoot = Get-Setting 'LAUNCHER_CSV_ALLOWED_ROOT' 'C:\data'
# Marca en la linea de comandos del launcher arrancado con esta configuracion comun.
$launcherMarker = '-Dbasketball.launcher.config=comun-v1'

$grafanaUrl = (Get-Setting 'GRAFANA_URL' 'http://localhost:8084').TrimEnd('/')
$grafanaUser = Get-Setting 'GRAFANA_USER' 'admin'
$grafanaPassword = Get-Setting 'GRAFANA_PASSWORD' 'local-dashboard-admin'
$grafanaContainer = 'basketball-grafana'
$pendingDashboardFile = Join-Path $batchRoot 'observability\fixtures-pending-dashboard.json'
$pendingDashboardUid = 'fixtures-audit-live'

$dependencies = @{
    grafana   = @('docker')
    # El watcher consulta PostgreSQL; asegurarlo antes evita arrancar Docker dos veces en paralelo.
    watcher   = @('postgres')
    postgres  = @('docker')
    runtime   = @('postgres')
    auditoria = @('postgres')
    launcher  = @('postgres')
}
$done = [System.Collections.Generic.HashSet[string]]::new()

function Write-Status([string]$Service, [string]$Message, [string]$Color = 'Gray') {
    $line = "[{0,-11}] {1}" -f $Service, $Message
    Write-Host $line -ForegroundColor $Color
    # Con ASEGURAR_LOG definido, cada linea se anade al log abriendo y cerrando el fichero:
    # no queda ningun handle abierto que los procesos arrancados aqui puedan heredar y bloquear.
    if ($env:ASEGURAR_LOG) { Add-Content -LiteralPath $env:ASEGURAR_LOG -Value $line -Encoding UTF8 }
}

function Wait-Until([string]$Service, [int]$Seconds, [scriptblock]$Test) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Test) { return }
        Start-Sleep -Seconds 2
    }
    throw "$Service no quedo listo tras $Seconds segundos."
}

function Invoke-Bat([string]$Name) {
    & $env:ComSpec /c ('"{0}"' -f (Join-Path $PSScriptRoot $Name))
    if ($LASTEXITCODE -ne 0) { throw "$Name termino con codigo $LASTEXITCODE" }
}

# En Windows PowerShell 5.1, con ErrorActionPreference=Stop, cualquier linea que un ejecutable
# escriba en stderr se convierte en excepcion. Docker parado escribe en stderr, asi que todas
# las llamadas a docker pasan por aqui con Continue y se juzgan solo por su codigo de salida.
function Invoke-Docker {
    $ErrorActionPreference = 'Continue'
    & docker @args 2>$null
}

function Invoke-DockerVisible {
    $ErrorActionPreference = 'Continue'
    & docker @args 2>&1 | ForEach-Object { Write-Host "  $_" }
}

function Test-Docker { Invoke-Docker info | Out-Null; return $LASTEXITCODE -eq 0 }

function Get-ContainerHealth([string]$ComposeService) {
    $id = Invoke-Docker compose -f $composeFile ps -q $ComposeService
    if (-not $id) { return 'missing' }
    $state = Invoke-Docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $id
    $status, $health = "$state".Split('|')
    if ($status -ne 'running') { return $status }
    if ($health -eq 'none') { return 'healthy' }
    return $health
}

function Ensure-Containers([string]$Service, [string[]]$ComposeServices, [int]$Seconds) {
    $pending = @($ComposeServices | Where-Object { (Get-ContainerHealth $_) -ne 'healthy' })
    if (-not $pending.Count) { Write-Status $Service 'ya estaba listo' Green; return }
    Write-Status $Service ("arrancando: {0}" -f ($pending -join ', ')) Yellow
    Invoke-DockerVisible compose -f $composeFile up -d @ComposeServices
    if ($LASTEXITCODE -ne 0) { throw "docker compose no pudo levantar $($ComposeServices -join ', ')." }
    Wait-Until $Service $Seconds { -not @($ComposeServices | Where-Object { (Get-ContainerHealth $_) -ne 'healthy' }).Count }
    Write-Status $Service 'listo' Green
}

function Get-Json([string]$Url) {
    try { return Invoke-RestMethod -Uri $Url -TimeoutSec 3 } catch { return $null }
}

function Get-LauncherProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" |
        Where-Object { $_.CommandLine -like '*csv-batch-launcher.jar*' })
}

function Start-Launcher {
    $jar = Join-Path $batchRoot 'launcher\target\csv-batch-launcher.jar'
    if (-not (Test-Path -LiteralPath $javaExe)) { throw "No se encontro Java 21: $javaExe" }
    if (-not (Test-Path -LiteralPath $jar)) {
        throw "No se encontro $jar. Compila desde csv-extra-batch con: mvn.cmd -B -DskipTests package"
    }
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

    # Configuracion unica del launcher; antes cada script la definia a su manera.
    $env:LAUNCHER_PORT = ([uri]$launcherUrl).Port
    $env:WATCH_DIRECTORY = $readyDir
    $env:CSV_ALLOWED_ROOT = $launcherAllowedRoot
    $env:LAUNCHER_DIRECTORY_SCAN_ENABLED = 'false'
    $env:JAVA_COMMAND = $javaExe
    $env:RESULTS_BATCH_JAR = "$batchRoot\results\target\csv-results-batch.jar"
    $env:FIXTURES_BATCH_JAR = "$batchRoot\fixtures\target\csv-fixtures-batch.jar"
    $env:TEAM_STATS_BATCH_JAR = "$batchRoot\team-stats\target\csv-team-stats-batch.jar"
    $env:MATCH_STATS_BATCH_JAR = "$batchRoot\match-summary\target\csv-stats-match-batch.jar"
    $env:PLAYER_STATS_BATCH_JAR = "$batchRoot\stats-player\target\csv-stats-player-batch.jar"
    $env:POINT_BY_POINT_BATCH_JAR = "$batchRoot\point-by-point\target\csv-point-by-point-batch.jar"

    Start-Detached $javaExe @($launcherMarker, '-jar', "`"$jar`"", "`"--logging.file.name=$reportDir\csv-batch-launcher.log`"") (Split-Path $jar -Parent) 0
}

function Start-Detached([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory, [int]$ShowWindow = 0) {
    # Arranca un proceso de larga duracion. El proceso hereda los ficheros abiertos de quien
    # llama, asi que este script no debe ejecutarse con la salida redirigida a un log que se
    # siga usando despues: para registrar, se usa ASEGURAR_LOG (ver Write-Status).
    # (Se probo a lanzarlos via WMI para evitar la herencia, pero el antivirus lo bloquea.)
    # ShowWindow: 0 = oculto, 7 = minimizado, 1 = normal.
    $style = @{ 0 = 'Hidden'; 7 = 'Minimized'; 1 = 'Normal' }[$ShowWindow]
    $start = @{ FilePath = $FilePath; WindowStyle = $style }
    if ($Arguments) { $start.ArgumentList = $Arguments }
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    Start-Process @start
}

function Ensure-Launcher {
    $processes = Get-LauncherProcesses
    $foreign = @($processes | Where-Object { $_.CommandLine -notlike "*$launcherMarker*" })
    $up = (Get-Json $launcherUrl).status -eq 'UP'

    if ($up -and -not $ReiniciarLauncher -and -not $foreign.Count) { Write-Status 'launcher' 'ya estaba listo' Green; return }

    if ($ReiniciarLauncher -or $foreign.Count) {
        $reason = if ($ReiniciarLauncher) { 'reinicio pedido' } else { 'estaba arrancado con otra configuracion' }
        Write-Status 'launcher' "reiniciando ($reason)" Yellow
        $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Wait-Until 'launcher (parada)' 30 { -not (Get-LauncherProcesses).Count }
        $processes = @()
    }

    if ($processes.Count) {
        # Hay un launcher nuestro arrancando: se espera en lugar de lanzar otro.
        Write-Status 'launcher' 'arrancando ya; esperando a que responda UP' Yellow
    } else {
        Write-Status 'launcher' 'arrancando' Yellow
        Start-Launcher
    }
    Wait-Until 'launcher' 120 { (Get-Json $launcherUrl).status -eq 'UP' }
    Write-Status 'launcher' "listo en $launcherUrl" Green
}

function Ensure-Auditoria {
    if (Get-Json "$auditUrl/latest") { Write-Status 'auditoria' 'ya estaba lista' Green; return }
    $running = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -like '*fixtures-processing-audit.jar*' })
    if ($running.Count) {
        Write-Status 'auditoria' 'arrancando ya; esperando a que responda' Yellow
    } else {
        $jar = Join-Path $batchRoot 'fixtures-processing-audit\target\fixtures-processing-audit.jar'
        if (-not (Test-Path -LiteralPath $javaExe)) { throw "No se encontro Java 21: $javaExe" }
        if (-not (Test-Path -LiteralPath $jar)) {
            throw "No se encontro $jar. Compila desde csv-extra-batch con: mvn.cmd -B -pl fixtures-processing-audit -am package -DskipTests"
        }
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
        Write-Status 'auditoria' 'arrancando' Yellow
        Start-Detached $javaExe @('-jar', "`"$jar`"", '--app.audit.run-once=false', "`"--logging.file.name=$reportDir\fixtures-processing-audit-service.log`"") (Split-Path $jar -Parent) 7
    }
    # La primera auditoria se lanza al arrancar; se espera a que termine.
    Wait-Until 'auditoria' 120 { (Get-Json "$auditUrl/latest").status -eq 'COMPLETED' }
    Write-Status 'auditoria' "lista en $auditUrl" Green
}

function Invoke-Grafana([string]$Method, [string]$Path, [string]$Body) {
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${grafanaUser}:${grafanaPassword}"))
    $request = @{ Method = $Method; Uri = "$grafanaUrl$Path"; Headers = @{ Authorization = "Basic $token" }; TimeoutSec = 15 }
    if ($Body) { $request.ContentType = 'application/json; charset=utf-8'; $request.Body = [Text.Encoding]::UTF8.GetBytes($Body) }
    Invoke-RestMethod @request
}

function Test-GrafanaResource([string]$Path) {
    try { Invoke-Grafana 'Get' $Path | Out-Null; return $true }
    catch { if ($_.Exception.Response.StatusCode.value__ -eq 404) { return $false }; throw }
}

function Ensure-Grafana {
    $state = Invoke-Docker inspect --format '{{.State.Status}}' $grafanaContainer
    if (-not $state) {
        throw "No existe el contenedor $grafanaContainer. Crealo una vez con: powershell -File local-validation\scripts\Start-BasketballLocal.ps1"
    }
    if ($state -ne 'running') {
        Write-Status 'grafana' "contenedor $state; arrancando" Yellow
        Invoke-DockerVisible start $grafanaContainer
        if ($LASTEXITCODE -ne 0) { throw "docker start $grafanaContainer fallo." }
    }
    Wait-Until 'grafana' 120 { try { (Invoke-RestMethod -Uri "$grafanaUrl/api/health" -TimeoutSec 3).database -eq 'ok' } catch { $false } }

    # Datasource Infinity que lee el JSON del modulo de pendientes (puerto 8090 del host).
    if (-not (Test-GrafanaResource '/api/datasources/uid/fixtures-audit-http')) {
        Write-Status 'grafana' 'creando datasource fixtures-audit-http' Yellow
        $datasource = @{ name = 'Fixtures Audit HTTP'; uid = 'fixtures-audit-http'; type = 'yesoreyeram-infinity-datasource'
                         access = 'proxy'; url = 'http://host.docker.internal:8090'; basicAuth = $false; isDefault = $false; jsonData = @{} }
        Invoke-Grafana 'Post' '/api/datasources' ($datasource | ConvertTo-Json -Depth 5) | Out-Null
    }

    if ($ActualizarDashboard -or -not (Test-GrafanaResource "/api/dashboards/uid/$pendingDashboardUid")) {
        if (-not (Test-Path -LiteralPath $pendingDashboardFile)) { throw "No se encontro $pendingDashboardFile" }
        Write-Status 'grafana' 'importando dashboard de pendientes' Yellow
        Invoke-Grafana 'Post' '/api/dashboards/db' (Get-Content -Raw -Encoding UTF8 -LiteralPath $pendingDashboardFile) | Out-Null
    }
    Write-Status 'grafana' "listo en $grafanaUrl/d/$pendingDashboardUid" Green
}

function Ensure-Docker {
    if (Test-Docker) { Write-Status 'docker' 'ya estaba listo' Green; return }
    if (-not (Test-Path -LiteralPath $dockerDesktop)) { throw "Docker Desktop no esta instalado en $dockerDesktop" }
    Write-Status 'docker' 'arrancando Docker Desktop' Yellow
    Start-Detached $dockerDesktop @() (Split-Path $dockerDesktop -Parent) 1
    Wait-Until 'docker' 180 { Test-Docker }
    Write-Status 'docker' 'listo' Green
}

function Ensure-Service([string]$Service) {
    if ($done.Contains($Service)) { return }
    foreach ($dependency in @($dependencies[$Service])) { if ($dependency) { Ensure-Service $dependency } }
    switch ($Service) {
        'antibloqueo' { Invoke-Bat 'INICIAR_ANTIBLOQUEO.bat' }
        'watcher'     { Invoke-Bat 'INICIAR_WATCHER_CSV.bat' }
        'docker'      { Ensure-Docker }
        'postgres'    { Ensure-Containers 'postgres' @('postgres') 120 }
        'runtime'     { Ensure-Containers 'runtime' @('postgres', 'mongo', 'basketball-match-projector', 'basketball-match-api', 'basketball-match-web') 300 }
        'auditoria'   { Ensure-Auditoria }
        'launcher'    { Ensure-Launcher }
        'grafana'     { Ensure-Grafana }
        default       { throw "Servicio desconocido: $Service. Validos: antibloqueo, watcher, docker, postgres, runtime, auditoria, launcher, grafana" }
    }
    [void]$done.Add($Service)
}

# Admite "postgres,launcher" y "postgres launcher".
$requested = @($Servicios | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
try {
    foreach ($service in $requested) { Ensure-Service $service }
} catch {
    Write-Status 'ERROR' $_.Exception.Message Red
    exit 1
}
exit 0
