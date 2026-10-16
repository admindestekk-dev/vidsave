@echo off
REM Wrapper so the logon scheduled task can launch the PowerShell script
REM without fighting nested quoting.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_backend.ps1"
