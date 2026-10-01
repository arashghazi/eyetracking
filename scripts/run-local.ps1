<#
.SYNOPSIS
  Runs the EyeTracking apps on this computer: research API, gaze service, Participant App and Research Admin.

.DESCRIPTION
  Pulls the latest code, prepares the Python environment, builds both Flutter web apps when the code
  changed, starts four local servers in the background and opens the two apps in the browser.
  Everything this script writes (database, media, passwords, logs) lives OUTSIDE the repository, in
  the data folder (default: a sibling folder named eyetracking-local). Nothing listens beyond this
  computer (127.0.0.1 only). Stop everything with scripts\stop-local.cmd.

.EXAMPLE
  scripts\run-local.cmd
  scripts\run-local.cmd -Model l2cs -Weights D:\Models\L2CSNet_gaze360.pkl
  scripts\run-local.cmd -Rebuild -NoPull
#>
[CmdletBinding()]
param(
  [ValidateSet('synthetic', 'l2cs')] [string]$Model = 'synthetic',
  [string]$Weights = '',
  [string]$Device = 'cpu',
  [string]$DataDir = '',
  [switch]$Rebuild,
  [switch]$NoPull,
  [switch]$NoDemo,
  [switch]$NoBrowser,
  [int]$ApiPort = 8000,
  [int]$GazePort = 8100,
  [int]$ParticipantPort = 8080,
  [int]$AdminPort = 5173
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $DataDir) { $DataDir = Join-Path (Split-Path -Parent $Repo) 'eyetracking-local' }
$LogDir = Join-Path $DataDir 'logs'
$MediaDir = Join-Path $DataDir 'media'
foreach ($d in @($DataDir, $LogDir, $MediaDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$DataDir = (Resolve-Path $DataDir).Path
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)
$SetupLog = Join-Path $LogDir 'setup.log'
"---- $(Get-Date -Format s) run-local" | Out-File -Append -FilePath $SetupLog

function Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Invoke-Logged([string]$what, [string]$exe, [string[]]$argv, [string]$cwd) {
  Step $what
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Push-Location $cwd
  try { & $exe @argv *>> $SetupLog; $code = $LASTEXITCODE } finally { Pop-Location; $ErrorActionPreference = $old }
  if ($code -ne 0) {
    Write-Host ((Get-Content $SetupLog -Tail 25) -join [Environment]::NewLine) -ForegroundColor Yellow
    throw "$what failed (exit code $code). Full log: $SetupLog"
  }
}

function Get-NativeOutput([string]$exe, [string[]]$argv) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & $exe @argv 2>$null; $code = $LASTEXITCODE } catch { $out = $null; $code = 1 } finally { $ErrorActionPreference = $old }
  if ($code -ne 0) { return $null }
  return ($out -join "`n")
}

function Require-Command([string]$name, [string]$hint) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "'$name' was not found on PATH. $hint" }
}

function Find-Python {
  foreach ($spec in @('py -3.13', 'py -3.12', 'py -3.11', 'py -3', 'python3', 'python')) {
    $parts = $spec -split ' '
    $exe = $parts[0]
    $pre = @($parts | Select-Object -Skip 1)
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
    $v = Get-NativeOutput $exe ($pre + @('-c', "import sys; print('%d.%d' % sys.version_info[:2])"))
    if ($v -and $v.Trim() -match '^\d+\.\d+$' -and ([version]$v.Trim() -ge [version]'3.11')) {
      return [pscustomobject]@{ Exe = $exe; Pre = $pre; Version = $v.Trim() }
    }
  }
  throw 'Python 3.11 or newer was not found. Install it from https://www.python.org/downloads/ and tick "Add python.exe to PATH".'
}

function New-Secret([int]$len = 20) {
  $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  $bytes = New-Object byte[] $len
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Test-Port([int]$port) {
  $client = New-Object System.Net.Sockets.TcpClient
  try { $client.Connect('127.0.0.1', $port); return $true } catch { return $false } finally { $client.Close() }
}

function Quote-Arg([string]$a) { if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' } return $a }

function Start-Server([string]$name, [string]$exe, [string[]]$argv, [string]$cwd) {
  $log = Join-Path $LogDir "$name.log"
  "---- $(Get-Date -Format s) start" | Out-File -Append -Encoding ascii -FilePath $log
  $all = @((Join-Path $PSScriptRoot 'run_server.py'), $log) + $argv
  $opts = @{ FilePath = $exe; ArgumentList = (($all | ForEach-Object { Quote-Arg $_ }) -join ' '); WorkingDirectory = $cwd; PassThru = $true }
  if ($OnWindows) { $opts.WindowStyle = 'Hidden' }
  $p = Start-Process @opts
  return [pscustomobject]@{ Name = $name; Process = $p; Err = $log }
}

function Wait-Http([string]$url, [int]$seconds, $server) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
      if ($r.StatusCode -eq 200) { return }
    } catch { }
    if ($server.Process.HasExited) { break }
    Start-Sleep -Milliseconds 700
  }
  if (Test-Path $server.Err) { Write-Host ((Get-Content $server.Err -Tail 20) -join [Environment]::NewLine) -ForegroundColor Yellow }
  throw "$($server.Name) did not start ($url). Log: $($server.Err)"
}

# ---------------------------------------------------------------- prerequisites
Step "Repository: $Repo"
Step "Data folder (database, media, passwords, logs): $DataDir"
Require-Command 'git' 'Install Git from https://git-scm.com/download/win.'
Require-Command 'flutter' 'Install Flutter 3.47 or newer (https://docs.flutter.dev/get-started/install/windows) and add its bin folder to PATH.'
$py = Find-Python
Step "Python $($py.Version) found ($((@($py.Exe) + $py.Pre) -join ' '))"
$fv = Get-NativeOutput 'flutter' @('--version', '--machine')
if ($fv -and $fv.IndexOf('{') -ge 0) {
  $info = $fv.Substring($fv.IndexOf('{'), $fv.LastIndexOf('}') - $fv.IndexOf('{') + 1) | ConvertFrom-Json
  $dart = ($info.dartSdkVersion -split '[ -]')[0]
  if ([version]$dart -lt [version]'3.13.4') { throw "Flutter $($info.frameworkVersion) has Dart $dart; the apps need Dart 3.13.4 or newer. Run: flutter upgrade" }
  Step "Flutter $($info.frameworkVersion) (Dart $dart) found"
} else { Write-Warning 'Could not read the Flutter version; continuing.' }

if ($Model -eq 'l2cs') {
  if (-not $Weights) { throw 'Model l2cs needs -Weights <path to the published L2CS-Net Gaze360 .pkl file>. See docs/run-local.fa.md.' }
  if (-not (Test-Path $Weights)) { throw "Weights file not found: $Weights" }
  $Weights = (Resolve-Path $Weights).Path
}

# ---------------------------------------------------------------- stop an earlier run
& (Join-Path $PSScriptRoot 'stop-local.ps1') -DataDir $DataDir -Quiet
foreach ($port in @($ApiPort, $GazePort, $ParticipantPort, $AdminPort)) {
  if (Test-Port $port) { throw "Port $port is already used by another program. Close it or pass another port, for example -ApiPort 8001." }
}

# ---------------------------------------------------------------- latest code
if (-not $NoPull -and (Test-Path (Join-Path $Repo '.git'))) {
  $dirty = Get-NativeOutput 'git' @('-C', $Repo, 'status', '--porcelain')
  if ($dirty) { Write-Warning 'The repository has local changes; skipping git pull.' }
  else {
    try { Invoke-Logged 'Getting the latest code (git pull)' 'git' @('-C', $Repo, 'pull', '--ff-only') $Repo }
    catch { Write-Warning "git pull failed; using the code already on this computer. ($($_.Exception.Message))" }
  }
}
$head = Get-NativeOutput 'git' @('-C', $Repo, 'rev-parse', '--short', 'HEAD')
if (-not $head) { $head = 'unknown' }
Step "Code version: $head"

# ---------------------------------------------------------------- python environment
$backend = Join-Path $Repo 'backend'
$venv = Join-Path $backend '.venv'
if ($OnWindows) { $vpy = Join-Path $venv 'Scripts\python.exe' } else { $vpy = Join-Path $venv 'bin/python' }
if (-not (Test-Path $vpy)) { Invoke-Logged 'Creating the Python environment (backend\.venv)' $py.Exe ($py.Pre + @('-m', 'venv', $venv)) $backend }
$extras = 'test,ai'
if ($Model -eq 'l2cs') { $extras = 'test,ai,l2cs' }
$pipStamp = Join-Path $DataDir 'pip-stamp.txt'
$wantStamp = (Get-FileHash (Join-Path $backend 'pyproject.toml')).Hash + "|$extras"
$haveStamp = ''
if (Test-Path $pipStamp) { $haveStamp = (Get-Content $pipStamp -Raw).Trim() }
if ($haveStamp -ne $wantStamp) {
  $msg = 'Installing backend packages (first time takes a few minutes)'
  if ($Model -eq 'l2cs') { $msg = 'Installing backend packages with PyTorch for L2CS (large download)' }
  Invoke-Logged $msg $vpy @('-m', 'pip', 'install', '--disable-pip-version-check', '-q', '-e', ".[$extras]") $backend
  Set-Content -Path $pipStamp -Value $wantStamp
}

# ---------------------------------------------------------------- flutter web builds
$apiUrl = "http://localhost:$ApiPort"
$gazeUrl = "http://localhost:$GazePort"
$partWeb = Join-Path $Repo 'apps\participant\build\web'
$adminWeb = Join-Path $Repo 'apps\admin\build\web'
if (-not $OnWindows) { $partWeb = $partWeb -replace '\\', '/'; $adminWeb = $adminWeb -replace '\\', '/' }
$buildStamp = Join-Path $DataDir 'build-stamp.txt'
$wantBuild = "$head|$ApiPort|$GazePort"
$haveBuild = ''
if (Test-Path $buildStamp) { $haveBuild = (Get-Content $buildStamp -Raw).Trim() }
$needBuild = $Rebuild -or ($haveBuild -ne $wantBuild) -or -not (Test-Path (Join-Path $partWeb 'index.html')) -or -not (Test-Path (Join-Path $adminWeb 'index.html'))
if ($needBuild) {
  Invoke-Logged 'Building the Participant App (Flutter web)' 'flutter' @('build', 'web', '--release', '--no-web-resources-cdn', "--dart-define=API_BASE_URL=$apiUrl", "--dart-define=GAZE_BASE_URL=$gazeUrl") (Join-Path $Repo 'apps/participant')
  Invoke-Logged 'Building the Research Admin (Flutter web)' 'flutter' @('build', 'web', '--release', '--no-web-resources-cdn', "--dart-define=API_BASE_URL=$apiUrl") (Join-Path $Repo 'apps/admin')
  Set-Content -Path $buildStamp -Value $wantBuild
} else { Step 'Web apps are up to date (use -Rebuild to force a build)' }

# ---------------------------------------------------------------- local secrets
$secretsFile = Join-Path $DataDir 'local-accounts.json'
if (Test-Path $secretsFile) { $sec = Get-Content $secretsFile -Raw | ConvertFrom-Json }
else {
  $sec = [pscustomobject]@{
    jwt_secret = (New-Secret 48)
    admin_email = 'admin@local.test'; admin_password = (New-Secret 16)
    researcher_email = 'researcher@local.test'; researcher_password = (New-Secret 16)
    participant_email = 'participant@local.test'; participant_password = (New-Secret 16)
  }
  $sec | ConvertTo-Json | Set-Content -Path $secretsFile
}

# ---------------------------------------------------------------- start servers
$dbFile = Join-Path $DataDir 'eyetracking.db'
$firstRun = -not (Test-Path $dbFile)
$env:EYETRACKING_DATABASE_URL = 'sqlite:///' + ($dbFile -replace '\\', '/')
$env:EYETRACKING_JWT_SECRET = $sec.jwt_secret
$env:EYETRACKING_BOOTSTRAP_ADMIN_EMAIL = $sec.admin_email
$env:EYETRACKING_BOOTSTRAP_ADMIN_PASSWORD = $sec.admin_password
$env:EYETRACKING_MEDIA_DIR = $MediaDir
$env:EYETRACKING_GAZE_IN_API = 'false'
$origins = @()
foreach ($p in @($ParticipantPort, $AdminPort)) { $origins += "http://localhost:$p"; $origins += "http://127.0.0.1:$p" }
$env:EYETRACKING_CORS_ORIGINS = ConvertTo-Json -Compress @($origins)
$env:EYETRACKING_GAZE_MODEL = $Model
$env:EYETRACKING_GAZE_DEVICE = $Device
if ($Weights) { $env:EYETRACKING_GAZE_WEIGHTS = $Weights } else { Remove-Item Env:EYETRACKING_GAZE_WEIGHTS -ErrorAction SilentlyContinue }

Step "Starting the gaze service on $gazeUrl (estimator: $Model)"
$gaze = Start-Server 'gaze' $vpy @('uvicorn', 'eyetracking.gaze.main:app', '--host', '127.0.0.1', '--port', "$GazePort") $backend
Step "Starting the research API on $apiUrl"
$api = Start-Server 'api' $vpy @('uvicorn', 'eyetracking.web.main:app', '--host', '127.0.0.1', '--port', "$ApiPort") $backend
Step 'Serving the Participant App and the Research Admin'
$part = Start-Server 'participant-web' $vpy @('http.server', "$ParticipantPort", '--bind', '127.0.0.1', '--directory', $partWeb) $Repo
$admin = Start-Server 'admin-web' $vpy @('http.server', "$AdminPort", '--bind', '127.0.0.1', '--directory', $adminWeb) $Repo
$servers = @($gaze, $api, $part, $admin)
[pscustomobject]@{ pids = @($servers | ForEach-Object { $_.Process.Id }); ports = @($ApiPort, $GazePort, $ParticipantPort, $AdminPort); started = (Get-Date -Format s) } |
  ConvertTo-Json | Set-Content -Path (Join-Path $DataDir 'servers.json')

$gazeWait = 60
if ($Model -eq 'l2cs') { $gazeWait = 240 }
Wait-Http "http://127.0.0.1:$GazePort/info" $gazeWait $gaze
Wait-Http "http://127.0.0.1:$ApiPort/health" 90 $api
Wait-Http "http://127.0.0.1:$ParticipantPort/" 30 $part
Wait-Http "http://127.0.0.1:$AdminPort/" 30 $admin
$gazeInfo = (Invoke-WebRequest -Uri "http://127.0.0.1:$GazePort/info" -UseBasicParsing).Content | ConvertFrom-Json

# ---------------------------------------------------------------- demo data
$demoFile = Join-Path $DataDir 'demo.json'
if ($firstRun -and -not $NoDemo) {
  Step 'Creating the demo study (first run only)'
  $seedArgs = @((Join-Path $PSScriptRoot 'seed_demo.py'), '--api', "http://127.0.0.1:$ApiPort", '--participant-url', "http://localhost:$ParticipantPort",
    '--admin-email', $sec.admin_email, '--admin-password', $sec.admin_password,
    '--researcher-email', $sec.researcher_email, '--researcher-password', $sec.researcher_password,
    '--participant-email', $sec.participant_email, '--participant-password', $sec.participant_password)
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $seedOut = (& $vpy @seedArgs 2>> $SetupLog) -join "`n"; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  if ($code -eq 0 -and $seedOut) { $seedOut | Set-Content -Path $demoFile } else { Write-Warning "The demo study could not be created; details at the end of $SetupLog" }
}
$demo = $null
if (Test-Path $demoFile) { $demo = Get-Content $demoFile -Raw | ConvertFrom-Json }

# ---------------------------------------------------------------- summary
Write-Host ''
Write-Host 'EyeTracking is running on this computer.' -ForegroundColor Green
Write-Host ''
Write-Host "  Research Admin   http://localhost:$AdminPort"
Write-Host "     administrator  $($sec.admin_email)  /  $($sec.admin_password)"
if ($demo -and -not $demo.skipped) { Write-Host "     researcher     $($sec.researcher_email)  /  $($sec.researcher_password)" }
Write-Host "  Participant App  http://localhost:$ParticipantPort"
if ($demo -and -not $demo.skipped) {
  Write-Host "     demo participant $($sec.participant_email)  /  $($sec.participant_password)  (code $($demo.participant_code), three practice paths assigned)"
  Write-Host "     new sign-up    $($demo.invitation_link)"
}
$synthetic = ''
if ($gazeInfo.synthetic) { $synthetic = '  SYNTHETIC: no accuracy, eye-region results stay blocked' }
Write-Host "  Gaze estimator   $($gazeInfo.model_id) $($gazeInfo.model_version)$synthetic"
Write-Host ''
Write-Host "  Accounts file    $secretsFile"
Write-Host "  Logs             $LogDir"
Write-Host "  Stop             scripts\stop-local.cmd"
Write-Host ''
if (-not $NoBrowser -and $OnWindows) {
  Start-Process "http://localhost:$AdminPort"
  Start-Process "http://localhost:$ParticipantPort"
}
