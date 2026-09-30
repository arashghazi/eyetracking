<#
.SYNOPSIS
  Stops the local servers started by scripts\run-local.ps1.
#>
[CmdletBinding()]
param([string]$DataDir = '', [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $DataDir) { $DataDir = Join-Path (Split-Path -Parent $Repo) 'eyetracking-local' }
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)
$state = Join-Path $DataDir 'servers.json'
if (-not (Test-Path $state)) { if (-not $Quiet) { Write-Host 'No running EyeTracking servers were recorded.' }; return }
$info = Get-Content $state -Raw | ConvertFrom-Json

function Stop-Tree([int]$procId) {
  if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { return }
  if ($OnWindows) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & taskkill.exe /PID $procId /T /F *> $null } catch { } finally { $ErrorActionPreference = $old }
  }
  else { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
}

foreach ($procId in @($info.pids)) { Stop-Tree ([int]$procId) }

# A Windows venv python.exe starts the real interpreter as a child; if one is still listening on our
# ports and it is one of ours (uvicorn eyetracking or http.server), stop it too.
if ($OnWindows -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
  foreach ($port in @($info.ports)) {
    $conns = Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -ErrorAction SilentlyContinue
    foreach ($c in @($conns)) {
      if (-not $c) { continue }
      $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($c.OwningProcess)" -ErrorAction SilentlyContinue
      if ($proc -and $proc.CommandLine -match 'eyetracking|http\.server') { Stop-Tree ([int]$c.OwningProcess) }
    }
  }
}
Remove-Item $state -ErrorAction SilentlyContinue
if (-not $Quiet) { Write-Host 'EyeTracking servers stopped.' -ForegroundColor Green }
