# ComfyUI Studio (Windows one-click setup)

Installs this repo as a desktop app on Windows, with its own private Python, so nothing else on the PC is touched.

## Install
Double-click **`Install ComfyUI Studio.bat`**. If Windows shows "Windows protected your PC", click **More info → Run anyway**.

The installer:
1. Installs Git if it's missing (via winget)
2. Clones `ajoey676/ComfyUI` and sets up a private Python 3.13 environment
3. Detects your GPU and installs the right PyTorch (NVIDIA CUDA, or CPU fallback)
4. Installs ComfyUI-Manager
5. Adds a **ComfyUI Studio** icon to the desktop and Start Menu
6. Optionally downloads the free Wan 2.2 5B video model (~18 GB)

## Where everything lives
```
C:\Users\<you>\ComfyUI Studio\
├── Open ComfyUI Studio      ← same as the desktop icon
├── Outputs\                 ← finished images & videos
├── Inputs\                  ← photos to animate / reference
├── Models\                  ← AI model files
├── Workflows\               ← saved workflows
├── Tools\
│   ├── Update ComfyUI
│   └── Download Video Models
├── ComfyUI\                 ← the code (this repo)
└── system\                  ← private Python, don't touch
```

## Using it
Double-click the desktop icon. A minimized "engine" window starts ComfyUI, then the app opens in its own window. Close the engine window to shut ComfyUI down.

## Updating
1. Bring new Comfy-Org releases into the GitHub repo (sync the fork, or ask Claude).
2. Run **Tools → Update ComfyUI**.

Re-running the installer is also safe: it repairs and updates in place.
