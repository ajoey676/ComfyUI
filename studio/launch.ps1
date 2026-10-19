# Starts ComfyUI (if it isn't already running), opens it in its own app window,
# and runs the Claude job inbox while it's open.
#
# Job inbox: drop files into  %USERPROFILE%\ComfyUI Studio\system\bridge\inbox
#   <name>.prompt.json    a ComfyUI API-format workflow -> queued in ComfyUI
#   <name>.download.json  {"url":"https://huggingface.co/...","dir":"checkpoints","name":"file.safetensors"}
# Results land in bridge\done\<name>.result.json; images/videos go to Outputs.
$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:USERPROFILE 'ComfyUI Studio'
$App  = Join-Path $Root 'ComfyUI'
$Py   = Join-Path $Root 'system\venv\Scripts\python.exe'
$Port = 8188
$Url  = "http://127.0.0.1:$Port"

$Bridge = Join-Path $Root 'system\bridge'
$Inbox  = Join-Path $Bridge 'inbox'
$Work   = Join-Path $Bridge 'processing'
$Done   = Join-Path $Bridge 'done'
foreach ($d in @($Inbox, $Work, $Done)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

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

function Write-Result($name, $obj) {
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path (Join-Path $Done "$name.result.json")
}

$Pending = @{}   # prompt_id -> job name
$AllowedDirs = @('checkpoints','diffusion_models','text_encoders','vae','loras','upscale_models','clip_vision','controlnet','unet','clip')

function Invoke-BridgeTick {
    # 1) pick up new jobs, oldest name first
    foreach ($f in (Get-ChildItem $Inbox -File -Filter '*.json' | Sort-Object Name)) {
        $job = Join-Path $Work $f.Name
        Move-Item -Force $f.FullName $job
        $name = $f.Name -replace '\.(prompt|download)\.json$', '' -replace '\.json$', ''
        try {
            if ($f.Name -like '*.download.json') {
                $d = Get-Content -Raw -Encoding UTF8 $job | ConvertFrom-Json
                if ($d.url -notlike 'https://huggingface.co/*') { throw 'Only huggingface.co downloads are allowed.' }
                if ($AllowedDirs -notcontains $d.dir) { throw "Folder '$($d.dir)' is not allowed." }
                if ($d.name -match '[\\/:]|\.\.') { throw 'Invalid file name.' }
                $dir = Join-Path $App "models\$($d.dir)"
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $dest = Join-Path $dir $d.name
                if (-not (Test-Path $dest)) {
                    Write-Host "[inbox] Downloading $($d.name)..." -ForegroundColor Cyan
                    & curl.exe -L --fail --retry 5 -C - -o "$dest.part" $d.url
                    if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit $LASTEXITCODE)." }
                    Move-Item -Force "$dest.part" $dest
                }
                Write-Result $name @{ status = 'done'; type = 'download'; path = $dest }
                Write-Host "[inbox] Downloaded $($d.name)" -ForegroundColor Green
                Remove-Item -Force $job
            } else {
                $raw  = Get-Content -Raw -Encoding UTF8 $job
                $body = '{"client_id":"claude-bridge","prompt":' + $raw + '}'
                $r = Invoke-RestMethod -Method Post -Uri "$Url/prompt" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
                $Pending[$r.prompt_id] = $name
                Write-Host "[inbox] Queued $name ($($r.prompt_id))" -ForegroundColor Cyan
                Remove-Item -Force $job
            }
        } catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            Write-Result $name @{ status = 'error'; error = $msg }
            Write-Host "[inbox] $name failed: $msg" -ForegroundColor Red
            Remove-Item -Force $job -ErrorAction SilentlyContinue
        }
    }

    # 2) check queued generations
    foreach ($id in @($Pending.Keys)) {
        try { $h = Invoke-RestMethod "$Url/history/$id" -TimeoutSec 5 } catch { continue }
        $entry = $h.$id
        if (-not $entry -or -not $entry.status) { continue }
        $finished = $entry.status.completed -or ($entry.status.status_str -eq 'error')
        if (-not $finished) { continue }
        $files = @()
        foreach ($node in $entry.outputs.PSObject.Properties) {
            foreach ($kind in @('images','gifs','videos','audio')) {
                foreach ($o in @($node.Value.$kind)) {
                    if ($o -and $o.filename) { $files += (Join-Path (Join-Path $Root 'Outputs') (Join-Path $o.subfolder $o.filename)) }
                }
            }
        }
        $ok = $entry.status.status_str -eq 'success'
        $res = @{ status = $(if ($ok) { 'done' } else { 'error' }); type = 'prompt'; prompt_id = $id; outputs = $files }
        if (-not $ok) { $res.error = ($entry.status.messages | ConvertTo-Json -Depth 6 -Compress) }
        Write-Result $Pending[$id] $res
        Write-Host "[inbox] $($Pending[$id]) finished: $($res.status)" -ForegroundColor Green
        $Pending.Remove($id)
    }
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

# Keep running the job inbox for as long as ComfyUI is up.
while (-not $proc.HasExited) {
    try { Invoke-BridgeTick } catch { Write-Host "[inbox] $($_.Exception.Message)" -ForegroundColor Red }
    Start-Sleep -Seconds 2
}

if ($proc.ExitCode -ne 0) {
    Write-Host "ComfyUI stopped with an error (code $($proc.ExitCode)). Scroll up to see why." -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
