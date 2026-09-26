<#
  Puts the GrowBuddy backend on the tailnet over HTTPS, and prints the exact
  `flutter run` line that points the app at it.

  Why this exists: the backend is normally reached at this machine's LAN IP,
  which stops working the moment the phone leaves the Wi-Fi. Tailscale gives the
  machine a stable name that follows it onto any network, and `tailscale serve`
  fronts the local uvicorn with a real Let's Encrypt certificate. That last part
  is what keeps Android happy — a cleartext http:// host would need an entry in
  network_security_config.xml and would never work in a release build.

  Nothing here is exposed to the public internet. Only devices signed into the
  same tailnet can reach it. `tailscale funnel` is the command that would make
  it public; this script deliberately does not use it.

  Usage:
    powershell -ExecutionPolicy Bypass -File tool\gb_tailscale_serve.ps1
    powershell -ExecutionPolicy Bypass -File tool\gb_tailscale_serve.ps1 -Off
#>
[CmdletBinding()]
param(
    # Local port uvicorn is listening on.
    [int]$Port = 8080,
    # Tear the proxy down again and exit.
    [switch]$Off
)

$ErrorActionPreference = 'Stop'

function Find-Tailscale {
    $onPath = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    # The installer does not always add itself to PATH.
    $candidates = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale IPN\tailscale.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

$ts = Find-Tailscale
if (-not $ts) {
    Write-Host "Tailscale is not installed on this machine." -ForegroundColor Red
    Write-Host ""
    Write-Host "  winget install --id Tailscale.Tailscale"
    Write-Host ""
    Write-Host "Then sign in (this opens a browser) and re-run this script:"
    Write-Host "  tailscale up"
    exit 1
}

if ($Off) {
    & $ts serve reset
    Write-Host "Tailscale serve stopped. The backend is LAN-only again." -ForegroundColor Yellow
    exit 0
}

# --- Is this node signed in? -------------------------------------------------
$statusJson = & $ts status --json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $statusJson) {
    Write-Host "Tailscale is installed but not running or not signed in." -ForegroundColor Red
    Write-Host "Run 'tailscale up' (opens a browser), then re-run this script."
    exit 1
}

$status = $statusJson | ConvertFrom-Json
if ($status.BackendState -ne 'Running') {
    Write-Host "Tailscale backend state is '$($status.BackendState)', expected 'Running'." -ForegroundColor Red
    Write-Host "Run 'tailscale up' and re-run this script."
    exit 1
}

# MagicDNS name comes back with a trailing dot: strip it.
$dnsName = $status.Self.DNSName
if (-not $dnsName) {
    Write-Host "This node has no MagicDNS name." -ForegroundColor Red
    Write-Host "Enable MagicDNS in the admin console: https://login.tailscale.com/admin/dns"
    exit 1
}
$host4 = $dnsName.TrimEnd('.')
$tailscaleIp = $status.Self.TailscaleIPs[0]

Write-Host "Node    : $host4"
Write-Host "Address : $tailscaleIp"

# --- Is the backend actually up? --------------------------------------------
# Serve will happily proxy to a dead port, and the failure then looks like a
# Tailscale problem from the phone. Check here instead.
$listening = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Host ""
    Write-Host "Warning: nothing is listening on port $Port." -ForegroundColor Yellow
    Write-Host "Start the backend first, from backend/ :"
    Write-Host "  .venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port $Port --reload"
    Write-Host ""
}

# --- Put it on the tailnet ---------------------------------------------------
# Newer CLIs take a bare port; older ones want the full proxy target. Try both
# before giving up, so this does not break on a Tailscale upgrade.
& $ts serve --bg --https=443 $Port 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $ts serve --bg --https=443 "http://127.0.0.1:$Port" 2>&1 | Out-Null
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "tailscale serve failed. Full output:" -ForegroundColor Red
    & $ts serve --bg --https=443 $Port
    Write-Host ""
    Write-Host "If it mentions certificates, enable HTTPS here:" -ForegroundColor Yellow
    Write-Host "  https://login.tailscale.com/admin/dns  ->  HTTPS Certificates"
    exit 1
}

$baseUrl = "https://$host4"

Write-Host ""
Write-Host "Backend is on the tailnet:" -ForegroundColor Green
Write-Host "  $baseUrl/health"
Write-Host "  $baseUrl/docs"
Write-Host ""
Write-Host "Run the app against it (phone must be signed into the same tailnet):"
Write-Host "  flutter run --dart-define=GB_API_BASE_URL=$baseUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Stop serving with:  tool\gb_tailscale_serve.ps1 -Off"
