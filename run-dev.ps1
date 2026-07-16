<#
.SYNOPSIS
  Lance l'environnement de dev Lumina d'un seul coup :
    1. Backend FastAPI (uvicorn, port 8000) dans une fenêtre séparée
    2. Tunnel `adb reverse tcp:8000 tcp:8000` (le device atteint le backend du PC)
    3. Frontend Flutter (`flutter run`) dans la fenêtre courante (hot reload dispo)

.PARAMETER Device
  ID du device Flutter (ex: 06d9297c0406). Par défaut : laisse Flutter choisir
  le seul device connecté.

.PARAMETER Web
  Lance le frontend dans Chrome. Dans ce cas l'app atteint le backend
  directement : pas besoin d'adb reverse (étape ignorée).

.PARAMETER NoBackend
  Ne (re)lance pas le backend (utile s'il tourne déjà dans une autre fenêtre).

.EXAMPLE
  .\run-dev.ps1
.EXAMPLE
  .\run-dev.ps1 -Device 06d9297c0406
.EXAMPLE
  .\run-dev.ps1 -Web
#>
param(
  [string]$Device = "",
  [switch]$Web,
  [switch]$NoBackend
)

$ErrorActionPreference = "Stop"

$Root     = $PSScriptRoot
$Backend  = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$Adb      = "C:\Users\wh\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$Port     = 8000

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    [!]  $msg" -ForegroundColor Yellow }

# --- Résolution de l'interpréteur Python (venv si présent, sinon global) -------
$Python = "python"
foreach ($p in @(
    (Join-Path $Backend ".venv\Scripts\python.exe"),
    (Join-Path $Backend "venv\Scripts\python.exe"))) {
  if (Test-Path $p) { $Python = $p; break }
}

# --- 1) Backend ----------------------------------------------------------------
if (-not $NoBackend) {
  Write-Step "Backend FastAPI (port $Port)"
  $listening = $null
  try {
    $listening = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
  } catch {}
  if ($listening) {
    Write-Ok "Déjà en écoute sur $Port — on ne relance pas (utilise -NoBackend pour masquer ce message)."
  } else {
    Write-Ok "Démarrage dans une nouvelle fenêtre…"
    $cmd = "Set-Location '$Backend'; & '$Python' -m uvicorn app.main:app --host 0.0.0.0 --port $Port"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd | Out-Null
  }
} else {
  Write-Step "Backend : ignoré (-NoBackend)"
}

# --- 2) adb reverse ------------------------------------------------------------
if (-not $Web) {
  Write-Step "Tunnel adb reverse tcp:$Port tcp:$Port"
  if (-not (Test-Path $Adb)) {
    Write-Warn2 "adb introuvable à $Adb — étape ignorée. Le login échouera sur device tant que le tunnel n'est pas posé."
  } else {
    $devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" }
    if (-not $devices) {
      Write-Warn2 "Aucun device ADB connecté. Branche la tablette (USB, débogage activé) puis relance, ou utilise -Web."
    } else {
      & $Adb reverse tcp:$Port tcp:$Port | Out-Null
      Write-Ok "Tunnel posé : $((& $Adb reverse --list) -join ', ')"
    }
  }
} else {
  Write-Step "adb reverse : ignoré (-Web, l'app Chrome atteint le backend directement)"
}

# --- 3) Attente que le backend réponde -----------------------------------------
if (-not $NoBackend) {
  Write-Step "Attente du backend…"
  $ready = $false
  for ($i = 0; $i -lt 20; $i++) {
    try {
      # 401 sur /v1/auth/me = backend vivant (pas de token) -> c'est OK.
      Invoke-WebRequest "http://127.0.0.1:$Port/v1/auth/me" -TimeoutSec 2 -UseBasicParsing | Out-Null
      $ready = $true; break
    } catch {
      if ($_.Exception.Response.StatusCode.value__ -eq 401) { $ready = $true; break }
      Start-Sleep -Milliseconds 700
    }
  }
  if ($ready) { Write-Ok "Backend joignable sur http://127.0.0.1:$Port" }
  else { Write-Warn2 "Backend pas encore joignable après ~14s — il finit peut-être de démarrer dans l'autre fenêtre." }
}

# --- 4) Frontend Flutter (fenêtre courante, interactif) ------------------------
Write-Step "Frontend Flutter"
Write-Host "    Compte de test : test@lumina.com / lumina123" -ForegroundColor DarkGray
Write-Host "    (r = hot reload, R = hot restart, q = quitter)`n" -ForegroundColor DarkGray

Set-Location $Frontend
if ($Web) {
  flutter run -d chrome
} elseif ($Device) {
  flutter run -d $Device
} else {
  flutter run
}
