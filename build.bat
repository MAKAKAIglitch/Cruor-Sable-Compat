@echo off
setlocal
cd /d "%~dp0"
title Cruor Sable Compat Builder

echo.
echo  Cruor Sable Compat Builder
echo  Minecraft 1.21.1 - NeoForge - Java 21
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    set "BUILD_EXIT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" %*
set "BUILD_EXIT=%ERRORLEVEL%"

:finish
echo.
if "%BUILD_EXIT%"=="0" (
    echo [OK] Build process finished successfully.
) else (
    echo [ERROR] Build process exited with code %BUILD_EXIT%.
    echo Keep this window open and send the error messages above.
)
echo.

rem Do not wait in CI environments such as GitHub Actions.
if defined CI exit /b %BUILD_EXIT%
if defined GITHUB_ACTIONS exit /b %BUILD_EXIT%

echo Press any key to close this window...
pause >nul
exit /b %BUILD_EXIT%
