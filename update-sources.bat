@echo off
setlocal
cd /d "%~dp0"
title Cruor Sable Compat Source Updater

echo.
echo  Cruor Sable Compat Source Updater
echo  Repository: MAKAKAIglitch/Cruor-Sable-Compat
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    set "UPDATE_EXIT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-sources.ps1"
set "UPDATE_EXIT=%ERRORLEVEL%"

:finish
echo.
if "%UPDATE_EXIT%"=="0" (
    echo [SUCCESS] Cruor Sable Compat sources have been updated from GitHub.
) else (
    echo [FAILED] Source update failed with exit code %UPDATE_EXIT%.
    echo Keep this window open and send the error messages above.
)
echo.

rem Do not wait in CI environments.
if defined CI exit /b %UPDATE_EXIT%
if defined GITHUB_ACTIONS exit /b %UPDATE_EXIT%

echo Press any key to close this window...
pause >nul
exit /b %UPDATE_EXIT%
