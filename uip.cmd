@echo off
REM =============================================================================
REM Portable Offline uip CLI Wrapper for Windows AVD / Corporate VMs
REM Routes native UiPath/skills "uip ..." commands to PCA's built-in offline emulator
REM when the official uip binary is not installed on the machine.
REM =============================================================================
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0pca.ps1" -Uip %*
exit /b %ERRORLEVEL%
