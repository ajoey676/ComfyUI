# Claude job inbox - reloaded by launch.ps1 every couple of seconds, so it can be
# improved without restarting ComfyUI Studio. Runs inside launch.ps1's scope
# ($Url, $App, $Root, $Inbox, $Work, $Done, $Pending come from there).

function Get-ModelFile($url, $dest) {
    # curl.exe first (resumable). --ssl-no-revoke skips only the certificate *revocation*
    # lookup, which often fails on Windows networks (curl exit 35); certificates are still verified.
    $code = 1
    try { & curl.exe -L --fail --retry 5 --ssl-no-revoke -C - -o "$dest.part" $url; $code = $LASTEXITCODE } catch { $code = -1 }
    if ($code -ne 0) {
        Write-Host "[inbox] curl failed (exit $code) - retrying with the Windows downloader..." -ForegroundColor Yellow
        Remove-Item -Force "$dest.part" -ErrorAction SilentlyContinue
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile "$dest.part" }
        finally { $ProgressPreference = $old }
    }
    Move-Item -Force "$dest.part" $dest
}

function Write-Result($name, $obj) {
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path (Join-Path $Done "$name.result.json")
}

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
                    Get-ModelFile $d.url $dest
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

