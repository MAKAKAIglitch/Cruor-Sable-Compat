@echo off
setlocal
cd /d "%~dp0"
title Cruor Sable Compat - Dependency Preloader

echo.
echo  Cruor Sable Compat - Dependency Preloader
echo  Minecraft 1.21.1 - NeoForge - Java 21
echo.
echo This downloads/resolves the dependencies required for future offline builds.
echo Cached files are stored in your normal Gradle User Home.
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    set "PREFETCH_EXIT=1"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" -Preload
set "PREFETCH_EXIT=%ERRORLEVEL%"

:finish
echo.
if "%PREFETCH_EXIT%"=="0" (
    echo [OK] Dependency preloading completed.
    echo You can now use build-offline.bat.
) else (
    echo [ERROR] Dependency preloading failed with code %PREFETCH_EXIT%.
    echo Send the complete output so the missing dependency can be identified.
)
echo.
if defined CI exit /b %PREFETCH_EXIT%
if defined GITHUB_ACTIONS exit /b %PREFETCH_EXIT%
echo Press any key to close this window...
pause >nul
exit /b %PREFETCH_EXIT%
