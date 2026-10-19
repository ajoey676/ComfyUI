# Downloads the free Wan 2.2 (5B) text/image-to-video model files into ComfyUI's models folder.
# Resumable: if it gets interrupted, just run it again.
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'

$Models = Join-Path $env:USERPROFILE 'ComfyUI Studio\ComfyUI\models'
$HF = 'https://huggingface.co/Comfy-Org'

$files = @(
    @{ Dir = 'diffusion_models'; Name = 'wan2.2_ti2v_5B_fp16.safetensors';        Url = "$HF/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"; Size = '10 GB' },
    @{ Dir = 'text_encoders';    Name = 'umt5_xxl_fp8_e4m3fn_scaled.safetensors'; Url = "$HF/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"; Size = '6.7 GB' },
    @{ Dir = 'vae';              Name = 'wan2.2_vae.safetensors';                 Url = "$HF/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors"; Size = '1.4 GB' }
)

Write-Host 'Downloading the Wan 2.2 video model (~18 GB total)...' -ForegroundColor Cyan
foreach ($f in $files) {
    $dir = Join-Path $Models $f.Dir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir $f.Name
    $part = "$dest.part"
    if (Test-Path $dest) { Write-Host "  [done] $($f.Name)" -ForegroundColor Green; continue }
    Write-Host "  Downloading $($f.Name) ($($f.Size))..."
    & curl.exe -L --fail --retry 5 -C - -o $part $f.Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed for $($f.Name). Check your internet and run this again - it resumes where it stopped." }
    Move-Item -Force $part $dest
}

Write-Host ''
Write-Host 'Video model ready. In ComfyUI: Workflow menu > Browse Templates > Video > "Wan 2.2 5B".' -ForegroundColor Green
if (-not $NoPause) { Read-Host 'Press Enter to close' }
