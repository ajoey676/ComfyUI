# Pulls the latest version of YOUR GitHub repo (ajoey676/ComfyUI) and refreshes Python packages.
# To bring in new releases from the original Comfy-Org project, sync your repo on GitHub first
# (or ask Claude to "update my ComfyUI repo"), then run this.
$ErrorActionPreference = 'Continue'

$Root = Join-Path $env:USERPROFILE 'ComfyUI Studio'
$App  = Join-Path $Root 'ComfyUI'
$Py   = Join-Path $Root 'system\venv\Scripts\python.exe'
$Uv   = Join-Path $Root 'system\uv\uv.exe'
$env:UV_CACHE_DIR = Join-Path $Root 'system\cache'

Write-Host 'Close ComfyUI Studio before updating.' -ForegroundColor Yellow
Write-Host ''
Write-Host '==> Pulling latest code from your GitHub repo' -ForegroundColor Cyan
git -C $App pull --ff-only
if ($LASTEXITCODE -ne 0) { Write-Host 'Update could not be applied automatically (local changes?). Ask Claude for help.' -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host '==> Updating Python packages' -ForegroundColor Cyan
& $Uv pip install --python $Py -r (Join-Path $App 'requirements.txt')
& $Uv pip install --python $Py -r (Join-Path $App 'manager_requirements.txt')

Write-Host ''
Write-Host 'Up to date. Open ComfyUI Studio from your desktop.' -ForegroundColor Green
Read-Host 'Press Enter to close'
