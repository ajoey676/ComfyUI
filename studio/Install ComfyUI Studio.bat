@echo off
title ComfyUI Studio installer
echo Downloading the latest ComfyUI Studio installer from github.com/ajoey676/ComfyUI ...
set "TMPPS=%TEMP%\comfyui-studio-install.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/ajoey676/ComfyUI/master/studio/install.ps1' -OutFile '%TMPPS%'"
if errorlevel 1 (
  echo Could not download the installer. Check your internet connection.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
if errorlevel 1 pause
