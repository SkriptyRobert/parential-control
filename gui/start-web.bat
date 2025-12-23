@echo off
chcp 65001 >nul
cls

echo.
echo =====================================================
echo   PARENTAL CONTROL - Web Server
echo =====================================================
echo.
echo   Tento server bezi na DETSKEM PC.
echo   Rodic se pripoji z mobilu nebo jineho PC.
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo   [CHYBA] Python neni nainstalovan!
    echo   Stahnete z https://python.org
    pause
    exit /b 1
)

:: Install Flask if needed
pip show flask >nul 2>&1
if errorlevel 1 (
    echo   Instaluji Flask...
    pip install flask flask-cors >nul
)

echo   Spoustim server...
echo.
echo =====================================================
echo.

python "%~dp0web-server.py"

pause
