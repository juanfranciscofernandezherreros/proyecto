# Unico punto de comprobacion y arranque de servicios.
# Para cada servicio pedido: comprueba si esta listo; si no, lo arranca y espera a que lo este.
# Las dependencias se resuelven solas (launcher -> postgres -> docker).
#
# Uso: ASEGURAR_SERVICIOS.ps1 -Servicios postgres,launcher [-ReiniciarLauncher] [-ActualizarDashboard]
# Servicios: antibloqueo, watcher, docker, postgres, runtime, auditoria, launcher, grafana, navegador, consumo
param(
    [Parameter(Mandatory)][string[]]$Servicios,
    [switch]$ReiniciarLauncher,
    # Reimporta el dashboard de pendientes aunque ya exista (pisa cambios hechos en la web).
    [switch]$ActualizarDashboard
)

$ErrorActionPreference = 'Stop'

# Rutas, JDK, URLs y credenciales: config\basketball.env (via scripts\config.ps1).
. (Join-Path $PSScriptRoot '..\config.ps1')
$workspace = $Config.WORKSPACE
$batchRoot = $Config.BATCH_ROOT
$reportDir = $Config.REPORT_DIR
$javaExe = $Config.JAVA_EXE
$dockerDesktop = $Config.DOCKER_DESKTOP
$composeFile = $Config.COMPOSE_FILE
$auditUrl = $Config.AUDIT_URL
$launcherUrl = $Config.LAUNCHER_URL.TrimEnd('/') + '/'
$competitionsDir = $Config.COMPETITIONS_DIR
$readyDir = $Config.READY_DIR
# Los importadores envian CSV de competitions\ y el pipeline por match_id de basketball-ready\;
# el launcher comun admite ambos para no tener que reiniciarlo segun quien lo use.
$launcherAllowedRoot = $Config.LAUNCHER_CSV_ALLOWED_ROOT
# Marca en la linea de comandos del launcher arrancado con esta configuracion comun.
$launcherMarker = '-Dbasketball.launcher.config=comun-v1'

$grafanaUrl = $Config.GRAFANA_URL.TrimEnd('/')
$grafanaUser = $Config.GRAFANA_USER
$grafanaPassword = $Config.GRAFANA_PASSWORD
$grafanaContainer = 'basketball-grafana'
# Dashboards que ASEGURAR grafana mantiene importados (uid -> fichero en csv-extra-batch\observability).
$grafanaDashboards = [ordered]@{
    'fixtures-audit-live' = Join-Path $batchRoot 'observability\fixtures-pending-dashboard.json'
    'processing-live'     = Join-Path $batchRoot 'observability\processing-live-dashboard.json'
    'csv-procesados'      = Join-Path $batchRoot 'observability\csv-procesados-dashboard.json'
    'consumo-recursos'    = Join-Path $batchRoot 'observability\consumo-recursos-dashboard.json'
}
$pendingDashboardUid = 'fixtures-audit-live'

$dependencies = @{
    grafana   = @('docker')
    # El watcher consulta PostgreSQL; asegurarlo antes evita arrancar Docker dos veces en paralelo.
    watcher   = @('postgres')
    postgres  = @('docker')
    runtime   = @('postgres')
    auditoria = @('postgres')
    launcher  = @('postgres')
    consumo   = @('postgres')
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

# La auditoria se repite cada pocos segundos. Si su ultimo resultado es antiguo, el servicio
# responde pero esta colgado (ya paso: bloqueado escribiendo en una consola congelada).
function Test-AuditoriaFresca {
    $latest = Get-Json "$auditUrl/latest"
    if (-not $latest -or -not $latest.refreshedAt) { return $false }
    # Java da 9 decimales en los segundos; .NET solo admite 7.
    $stamp = $latest.refreshedAt -replace '(\.\d{7})\d+', '$1'
    try { $age = (Get-Date) - [datetimeoffset]::Parse($stamp, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime } catch { return $false }
    return $age.TotalMinutes -lt 2
}

function Get-AuditoriaProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -like '*fixtures-processing-audit.jar*' })
}

function Ensure-Auditoria {
    if (Test-AuditoriaFresca) { Write-Status 'auditoria' 'ya estaba lista' Green; return }
    $running = Get-AuditoriaProcesses
    if ($running.Count -and (Get-Json "$auditUrl/latest")) {
        # Responde pero no refresca: esta colgada. Se reinicia.
        Write-Status 'auditoria' 'responde pero lleva mas de 2 minutos sin refrescar; reiniciando' Yellow
        $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Wait-Until 'auditoria (parada)' 30 { -not (Get-AuditoriaProcesses).Count }
        $running = @()
    }
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
        # Oculta y sin salida por consola (--logging.pattern.console= la desactiva): una consola
        # congelada por un clic bloqueaba el hilo de la auditoria. El log va solo a su fichero.
        $env:FIXTURES_PROCESSING_AUDIT_LEAGUE_CATALOG = $Config.LEAGUE_CATALOG
        Start-Detached $javaExe @('-jar', "`"$jar`"", '--app.audit.run-once=false', '--logging.pattern.console=',
            "`"--logging.file.name=$reportDir\fixtures-processing-audit-service.log`"") (Split-Path $jar -Parent) 0
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
    # Prometheus y Loki son las fuentes de datos de Grafana: sin ellos los dashboards salen vacios.
    # No son imprescindibles para Grafana, asi que un fallo solo se avisa.
    foreach ($source in @('basketball-prometheus', 'basketball-loki')) {
        $sourceState = Invoke-Docker inspect --format '{{.State.Status}}' $source
        if (-not $sourceState) { Write-Status 'grafana' "no existe el contenedor $source" Yellow; continue }
        if ($sourceState -ne 'running') {
            Write-Status 'grafana' "$source $sourceState; arrancando" Yellow
            Invoke-DockerVisible start $source
            if ($LASTEXITCODE -ne 0) { Write-Status 'grafana' "docker start $source fallo" Yellow }
        }
    }
    $state = Invoke-Docker inspect --format '{{.State.Status}}' $grafanaContainer
    if (-not $state) {
        throw "No existe el contenedor $grafanaContainer. Crealo una vez con: powershell -File local-validation\scripts\Start-BasketballLocal.ps1"
    }
    if ($state -ne 'running') {
        Write-Status 'grafana' "contenedor $state; arrancando" Yellow
        Invoke-DockerVisible start $grafanaContainer
        if ($LASTEXITCODE -ne 0) { throw "docker start $grafanaContainer fallo." }
    }
    $healthy = { try { (Invoke-RestMethod -Uri "$grafanaUrl/api/health" -TimeoutSec 3).database -eq 'ok' } catch { $false } }
    if ($state -eq 'running') {
        # En marcha pero sin responder (p. ej. sin memoria): se reinicia en vez de esperar.
        try { Wait-Until 'grafana' 20 $healthy } catch {
            Write-Status 'grafana' 'en marcha pero no responde; reiniciando' Yellow
            Invoke-DockerVisible restart $grafanaContainer
        }
    }
    Wait-Until 'grafana' 120 $healthy

    # Datasource Infinity que lee el JSON del modulo de pendientes (puerto 8090 del host).
    if (-not (Test-GrafanaResource '/api/datasources/uid/fixtures-audit-http')) {
        Write-Status 'grafana' 'creando datasource fixtures-audit-http' Yellow
        $datasource = @{ name = 'Fixtures Audit HTTP'; uid = 'fixtures-audit-http'; type = 'yesoreyeram-infinity-datasource'
                         access = 'proxy'; url = 'http://host.docker.internal:8090'; basicAuth = $false; isDefault = $false; jsonData = @{} }
        Invoke-Grafana 'Post' '/api/datasources' ($datasource | ConvertTo-Json -Depth 5) | Out-Null
    }

    foreach ($uid in $grafanaDashboards.Keys) {
        if ($ActualizarDashboard -or -not (Test-GrafanaResource "/api/dashboards/uid/$uid")) {
            $file = $grafanaDashboards[$uid]
            if (-not (Test-Path -LiteralPath $file)) { throw "No se encontro $file" }
            Write-Status 'grafana' "importando dashboard $uid" Yellow
            Invoke-Grafana 'Post' '/api/dashboards/db' (Get-Content -Raw -Encoding UTF8 -LiteralPath $file) | Out-Null
        }
    }
    Write-Status 'grafana' "listo en $grafanaUrl/d/$pendingDashboardUid" Green
}

# Recolector de CPU, RAM, heap, base y disco para el dashboard consumo-recursos.
function Get-ConsumoProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*RECOLECTAR_CONSUMO.ps1*' })
}

function Ensure-Consumo {
    if (@(Get-ConsumoProcesses).Count) { Write-Status 'consumo' 'ya estaba en marcha' Green; return }
    Write-Status 'consumo' 'arrancando recolector' Yellow
    $script = Join-Path $workspace 'scripts\monitor\RECOLECTAR_CONSUMO.ps1'
    Start-Detached 'powershell.exe' @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"") $workspace 0
    # @(): con un solo proceso la funcion devuelve el objeto suelto y .Count no existe.
    Wait-Until 'consumo' 30 { @(Get-ConsumoProcesses).Count }
    Write-Status 'consumo' 'en marcha (log en reports\consumo\recolector-consumo.log)' Green
}

# Con FLASHSCORE_BROWSER=edge, el driver de Edge debe coincidir con la version instalada.
function Ensure-Navegador {
    if ($Config.FLASHSCORE_BROWSER -ne 'edge') { Write-Status 'navegador' "usa $($Config.FLASHSCORE_BROWSER); nada que comprobar" Green; return }
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ACTUALIZAR_EDGEDRIVER.ps1') 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Status 'navegador' "$_" $(if ($code) { 'Red' } else { 'Green' }) }
    if ($code) { throw 'el driver de Edge no esta disponible.' }
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
        'navegador'   { Ensure-Navegador }
        'consumo'     { Ensure-Consumo }
        default       { throw "Servicio desconocido: $Service. Validos: antibloqueo, watcher, docker, postgres, runtime, auditoria, launcher, grafana, navegador, consumo" }
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
