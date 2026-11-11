@echo off
REM Portable Coding Assistant (pca) - Zero-Dependency Windows AVD Launcher
REM Automatically bypasses PowerShell ExecutionPolicy restrictions for the current process.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0pca.ps1" %*
exit /b %ERRORLEVEL%
