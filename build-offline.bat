@echo off
setlocal
cd /d "%~dp0"
title Cruor Sable Compat - Offline Builder

echo.
echo  Cruor Sable Compat - Offline Builder
echo  This build uses only artifacts already stored in the Gradle cache.
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    set "BUILD_EXIT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" -Offline
set "BUILD_EXIT=%ERRORLEVEL%"

:finish
echo.
if "%BUILD_EXIT%"=="0" (
    echo [OK] Offline build completed successfully.
) else (
    echo [ERROR] Offline build failed with code %BUILD_EXIT%.
    echo The output should identify the first dependency missing from the local cache.
)
echo.
if defined CI exit /b %BUILD_EXIT%
if defined GITHUB_ACTIONS exit /b %BUILD_EXIT%
echo Press any key to close this window...
pause >nul
exit /b %BUILD_EXIT%
