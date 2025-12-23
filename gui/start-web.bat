@echo off
echo ========================================
echo   Parental Control Web Server
echo ========================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo Python neni nainstalovan!
    echo Stahnete z https://python.org
    pause
    exit /b 1
)

:: Install requirements
pip show flask >nul 2>&1
if errorlevel 1 (
    echo Instaluji Flask...
    pip install flask flask-cors
)

echo.
echo Spoustim server na http://localhost:5000
echo.
echo Prihlaseni: admin / parental123
echo Zmenit v souboru web-server.py
echo.

python "%~dp0web-server.py"

