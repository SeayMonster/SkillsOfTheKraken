@echo off
echo Installing SkillsOfTheKraken for Claude Desktop...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0addclaudeskills.ps1"
echo.
pause
