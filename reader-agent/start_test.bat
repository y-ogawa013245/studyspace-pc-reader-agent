@echo off
chcp 65001 > nul
echo =======================================================
echo    StudySpace - RC-S300 FeliCa リーダーテスト起動
echo =======================================================
echo.
cd /d %~dp0
.\python\python.exe -u test_reader.py
pause
