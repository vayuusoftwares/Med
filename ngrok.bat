@echo off
setlocal enabledelayedexpansion
title NGROK HTTPS Tunnel (WAMP Port 80)

echo ========================================================
echo Starting NGROK HTTPS Tunnel on WAMP Apache (Port 80)...
echo ========================================================

:: 1. Prevent duplicate ngrok processes / tunnels
tasklist /FI "IMAGENAME eq ngrok.exe" 2>NUL | find /I /N "ngrok.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo.
    echo [INFO] ngrok is already running. Preventing duplicate tunnel instance.
    echo.
    ping 127.0.0.1 -n 5 >nul
    exit /b 0
)

:: 2. Short delay so WAMP / Apache has time to start
echo Waiting 10 seconds for WAMP / Apache to initialize...
ping 127.0.0.1 -n 11 >nul

:: 3. Find ngrok executable
set "NGROK_EXE="
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\ngrok.exe" set "NGROK_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\ngrok.exe"
if not defined NGROK_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe" set "NGROK_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe"
if not defined NGROK_EXE if exist "%USERPROFILE%\Downloads\ngrok-v3-stable-windows-amd64\ngrok.exe" set "NGROK_EXE=%USERPROFILE%\Downloads\ngrok-v3-stable-windows-amd64\ngrok.exe"
if not defined NGROK_EXE if exist "%LOCALAPPDATA%\ngrok\ngrok.exe" set "NGROK_EXE=%LOCALAPPDATA%\ngrok\ngrok.exe"
if not defined NGROK_EXE if exist "%~dp0ngrok.exe" set "NGROK_EXE=%~dp0ngrok.exe"
if not defined NGROK_EXE (
    where ngrok >nul 2>&1
    if !ERRORLEVEL! EQU 0 set "NGROK_EXE=ngrok"
)

if not defined NGROK_EXE (
    echo.
    echo [ERROR] ngrok.exe was not found. Please ensure ngrok is installed.
    echo.
    pause
    exit /b 1
)

echo.
echo Tunneling Port 80 with: "!NGROK_EXE!"
echo Keep this window open while using the tunnel.
echo ========================================================
echo.

"!NGROK_EXE!" http 80

pause
