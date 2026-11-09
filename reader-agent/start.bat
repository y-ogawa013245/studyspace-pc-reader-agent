@echo off
setlocal
title StudySpace Reader Agent

cd /d "%~dp0"

if exist "StudySpace.exe" (
    start "" "StudySpace.exe"
    exit /b 0
)

if exist ".core\StudySpace.exe" (
    start "" ".core\StudySpace.exe"
    exit /b 0
)

if exist ".core\python\python.exe" (
    ".core\python\python.exe" -u ".core\reader_agent.py"
    exit /b %ERRORLEVEL%
)

if exist "python\python.exe" (
    "python\python.exe" -u "reader_agent.py"
    exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host '[ERROR] Python environment not found. Please run setup.exe first.' -ForegroundColor Red; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('内蔵環境が見つかりません。先に setup.exe を実行してください。', 'StudySpace エラー', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null"
pause
exit /b 1
