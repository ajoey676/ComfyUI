# Starts ComfyUI (if it isn't already running) and opens it in its own app window.
$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:USERPROFILE 'ComfyUI Studio'
$App  = Join-Path $Root 'ComfyUI'
$Py   = Join-Path $Root 'system\venv\Scripts\python.exe'
$Port = 8188
$Url  = "http://127.0.0.1:$Port"

$Host.UI.RawUI.WindowTitle = 'ComfyUI Studio - engine (close this window to stop ComfyUI)'

function Test-Up {
    try { Invoke-WebRequest "$Url/system_stats" -UseBasicParsing -TimeoutSec 2 | Out-Null; $true } catch { $false }
}

function Open-AppWindow {
    $edge = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process $edge "--app=$Url" }
    else { Start-Process $Url }
}

if (-not (Test-Path $Py)) {
    Write-Host 'ComfyUI Studio is not installed yet. Run the installer first.' -ForegroundColor Red
    Read-Host 'Press Enter to close'; exit 1
}

if (Test-Up) { Open-AppWindow; exit 0 }

# Paths contain spaces, so build one properly quoted argument string.
$comfyArgs = "main.py --port $Port --enable-manager --disable-auto-launch " +
             "--output-directory `"$(Join-Path $Root 'Outputs')`" " +
             "--input-directory `"$(Join-Path $Root 'Inputs')`""
if ((Get-Content (Join-Path $Root 'system\gpu.txt') -ErrorAction SilentlyContinue | Select-Object -First 1) -eq 'cpu') {
    $comfyArgs += ' --cpu'
}

$proc = Start-Process -FilePath $Py -ArgumentList $comfyArgs -WorkingDirectory $App -NoNewWindow -PassThru

Write-Host 'Starting ComfyUI... the app window opens when it is ready.' -ForegroundColor Cyan
for ($i = 0; $i -lt 180; $i++) {
    if ($proc.HasExited) { break }
    if (Test-Up) { Open-AppWindow; break }
    Start-Sleep -Seconds 1
}

$proc.WaitForExit()
if ($proc.ExitCode -ne 0) {
    Write-Host "ComfyUI stopped with an error (code $($proc.ExitCode)). Scroll up to see why." -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
