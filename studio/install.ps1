# ComfyUI Studio installer for Windows
# Installs ajoey676/ComfyUI into "%USERPROFILE%\ComfyUI Studio" with its own
# private Python, then adds a desktop + Start Menu icon. Safe to re-run: it
# repairs/updates an existing install instead of starting over.

# 'Continue' so progress text that git/uv print to stderr isn't treated as a failure;
# real failures are caught with Check-Exit after each command.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$RepoUrl   = 'https://github.com/ajoey676/ComfyUI.git'
$Root      = Join-Path $env:USERPROFILE 'ComfyUI Studio'
$App       = Join-Path $Root 'ComfyUI'
$System    = Join-Path $Root 'system'
$Venv      = Join-Path $System 'venv'
$Py        = Join-Path $Venv 'Scripts\python.exe'
$UvDir     = Join-Path $System 'uv'
$Uv        = Join-Path $UvDir 'uv.exe'

function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Check-Exit($what) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "  Install failed while: $what (exit code $LASTEXITCODE)" -ForegroundColor Red
        Write-Host '  Scroll up for details, or send a screenshot to Claude. Re-running the installer is safe.'
        Read-Host '  Press Enter to close'; exit 1
    }
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Host ''
Write-Host '  ComfyUI Studio - installer' -ForegroundColor Magenta
Write-Host "  Installing to: $Root"
Write-Host '  This takes 10-20 minutes (several GB of downloads). Leave this window open.'

# ---------------------------------------------------------------- folders
Step 'Creating folders'
foreach ($d in @($Root, $System, 'Outputs', 'Inputs', 'Tools')) {
    $p = if ([IO.Path]::IsPathRooted($d)) { $d } else { Join-Path $Root $d }
    New-Item -ItemType Directory -Force -Path $p | Out-Null
}

# ---------------------------------------------------------------- git
Step 'Checking for Git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed and winget is unavailable. Install Git from https://git-scm.com/download/win and run this installer again.'
    }
    Info 'Installing Git (one-time)...'
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    Refresh-Path
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $gitExe = 'C:\Program Files\Git\cmd'
        if (Test-Path $gitExe) { $env:Path += ";$gitExe" } else { throw 'Git install did not finish. Restart your PC and run the installer again.' }
    }
}
Info (git --version)

# ---------------------------------------------------------------- code
Step 'Getting ComfyUI from your GitHub repo'
if (Test-Path (Join-Path $App '.git')) {
    Info 'Existing install found - updating it.'
    git -C $App pull --ff-only | Out-Host; Check-Exit 'updating the code'
} else {
    git clone $RepoUrl $App | Out-Host; Check-Exit 'downloading the code'
}
if ((git -C $App remote) -notcontains 'upstream') { git -C $App remote add upstream https://github.com/Comfy-Org/ComfyUI.git }

# ---------------------------------------------------------------- python
Step 'Setting up a private Python (does not touch any other Python on this PC)'
if (-not (Test-Path $Uv)) {
    $env:UV_INSTALL_DIR = $UvDir
    $env:UV_NO_MODIFY_PATH = '1'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    if (-not (Test-Path $Uv)) { throw 'Could not install uv (the Python manager). Check your internet and re-run.' }
}
$env:UV_PYTHON_INSTALL_DIR = Join-Path $System 'python'
$env:UV_CACHE_DIR = Join-Path $System 'cache'
if (-not (Test-Path $Py)) { & $Uv venv --python 3.13 $Venv | Out-Host; Check-Exit 'creating the Python environment' }

# ---------------------------------------------------------------- gpu
Step 'Detecting your graphics card'
$gpuName = ''; $vramGB = 0
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $q = (nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | Select-Object -First 1)
    if ($q) { $parts = $q.Split(','); $gpuName = $parts[0].Trim(); $vramGB = [math]::Round([double]$parts[1].Trim() / 1024) }
}
$allGpus = @(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name)
if (-not $gpuName) {
    # Prefer a dedicated card (AMD/NVIDIA) over built-in Intel graphics.
    $gpuName = ($allGpus | Where-Object { $_ -match 'Radeon|NVIDIA|GeForce' } | Select-Object -First 1)
    if (-not $gpuName) { $gpuName = ($allGpus | Where-Object { $_ -match 'Arc' } | Select-Object -First 1) }
    if (-not $gpuName) { $gpuName = $allGpus | Select-Object -First 1 }
}
Info "Graphics found: $($allGpus -join ', ')"
Info "Using: $gpuName $(if ($vramGB) { "($vramGB GB)" })"

if ($vramGB -gt 0) {
    if ($gpuName -match 'GTX (9|10)\d\d') { $torchIndex = 'https://download.pytorch.org/whl/cu126' }
    else { $torchIndex = 'https://download.pytorch.org/whl/cu130' }
    $mode = 'nvidia'
} elseif ($gpuName -match 'Intel.*Arc') {
    Info 'Intel Arc graphics - installing the Intel GPU (XPU) version of PyTorch.'
    $torchIndex = 'https://download.pytorch.org/whl/xpu'
    $mode = 'xpu'
} else {
    Warn 'No supported GPU detected. Installing the CPU version - it will run, but generation will be slow.'
    $torchIndex = 'https://download.pytorch.org/whl/cpu'
    $mode = 'cpu'
}
$gpuFile = Join-Path $System 'gpu.txt'
$prevMode = if (Test-Path $gpuFile) { Get-Content $gpuFile | Select-Object -First 1 } else { '' }
Set-Content -Path $gpuFile -Value "$mode`n$gpuName`n$vramGB"

# ---------------------------------------------------------------- packages
Step 'Installing PyTorch (largest download, ~3 GB)'
$reinstall = @()
if ($prevMode -and $prevMode -ne $mode) { Info "Switching PyTorch from '$prevMode' to '$mode'."; $reinstall = @('--reinstall-package','torch','--reinstall-package','torchvision','--reinstall-package','torchaudio') }
& $Uv pip install --python $Py torch torchvision torchaudio --extra-index-url $torchIndex @reinstall | Out-Host
Check-Exit 'installing PyTorch'

Step 'Installing ComfyUI requirements + ComfyUI-Manager'
& $Uv pip install --python $Py -r (Join-Path $App 'requirements.txt') | Out-Host
Check-Exit 'installing ComfyUI requirements'
& $Uv pip install --python $Py -r (Join-Path $App 'manager_requirements.txt') | Out-Host
Check-Exit 'installing ComfyUI-Manager'

# ---------------------------------------------------------------- organize
Step 'Organizing folders'
$links = @{
    'Models'    = Join-Path $App 'models'
    'Workflows' = Join-Path $App 'user\default\workflows'
}
foreach ($name in $links.Keys) {
    $target = $links[$name]
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $link = Join-Path $Root $name
    if (-not (Test-Path $link)) { New-Item -ItemType Junction -Path $link -Target $target | Out-Null }
}

# ---------------------------------------------------------------- shortcuts
Step 'Creating your app icon'
$Studio = Join-Path $App 'studio'
$Icon   = Join-Path $Studio 'comfyui-studio.ico'
$Ps     = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Shell  = New-Object -ComObject WScript.Shell

function New-Shortcut($path, $script, $desc, $style = 7) {
    $s = $Shell.CreateShortcut($path)
    $s.TargetPath = $Ps
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Studio $script)`""
    $s.WorkingDirectory = $Root
    $s.IconLocation = "$Icon,0"
    $s.Description = $desc
    $s.WindowStyle = $style   # 7 = minimized, 1 = normal
    $s.Save()
}

$desktop   = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'ComfyUI Studio'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null

New-Shortcut (Join-Path $desktop   'ComfyUI Studio.lnk') 'launch.ps1' 'Open ComfyUI Studio'
New-Shortcut (Join-Path $startMenu 'ComfyUI Studio.lnk') 'launch.ps1' 'Open ComfyUI Studio'
New-Shortcut (Join-Path $Root      'Open ComfyUI Studio.lnk') 'launch.ps1' 'Open ComfyUI Studio'
New-Shortcut (Join-Path $Root 'Tools\Update ComfyUI.lnk') 'update.ps1' 'Update ComfyUI from your GitHub repo' 1
New-Shortcut (Join-Path $Root 'Tools\Download Video Models.lnk') 'download-models.ps1' 'Download the Wan 2.2 video model' 1
New-Shortcut (Join-Path $startMenu 'Update ComfyUI.lnk') 'update.ps1' 'Update ComfyUI' 1

# ---------------------------------------------------------------- models
Step 'Video model'
if ($mode -eq 'nvidia' -and $vramGB -ge 8) {
    $ans = Read-Host '    Download the free Wan 2.2 video model now? (~18 GB) [Y/n]'
    if ($ans -notmatch '^[nN]') { & $Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Studio 'download-models.ps1') -NoPause }
    else { Info 'Skipped. Run "Tools\Download Video Models" any time.' }
} else {
    Warn 'Your GPU has under 8 GB of video memory, so the video model was not downloaded automatically.'
    Info 'You can still try it later from Tools\Download Video Models.'
}

# ---------------------------------------------------------------- done
Write-Host ''
Write-Host '  All done!' -ForegroundColor Green
Write-Host "  - Double-click 'ComfyUI Studio' on your desktop to start."
Write-Host "  - Everything lives in: $Root"
Write-Host '      Outputs   -> your finished images and videos'
Write-Host '      Inputs    -> photos you want to animate'
Write-Host '      Models    -> AI model files'
Write-Host '      Workflows -> saved workflows'
Write-Host '      Tools     -> Update / Download models'
Write-Host ''
Start-Process explorer.exe $Root
Read-Host '  Press Enter to close'
