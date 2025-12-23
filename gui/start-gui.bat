@echo off
echo Starting Parental Control GUI...
echo.

:: Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo Python is not installed!
    echo Please install Python from https://python.org
    pause
    exit /b 1
)

:: Install requirements if needed
pip show customtkinter >nul 2>&1
if errorlevel 1 (
    echo Installing required packages...
    pip install -r "%~dp0requirements.txt"
)

:: Run the GUI
python "%~dp0parental-control-gui.py"

