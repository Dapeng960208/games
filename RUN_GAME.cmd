@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1"
if errorlevel 1 (
  echo The game could not start. Check the tools\godot files.
  pause
  exit /b 1
)