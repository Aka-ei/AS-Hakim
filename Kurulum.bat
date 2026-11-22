@echo off
setlocal
chcp 65001 >nul
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Yama_Dosyalari\kurulum_yardimci.ps1"

if not exist "%PS_SCRIPT%" goto :missing_script

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -PackageRoot "%SCRIPT_DIR%."
endlocal
exit /b %ERRORLEVEL%

:missing_script
echo [HATA] Kurulum yardimci dosyasi bulunamadi:
echo %PS_SCRIPT%
echo.
echo Lutfen arsivi [ZIP/RAR] once bir klasore cikarin, ardindan Kurulum.bat dosyasini calistirin.
pause
endlocal
exit /b 1
