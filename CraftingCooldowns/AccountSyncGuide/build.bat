@echo off
setlocal EnableDelayedExpansion

echo ============================================================
echo   CraftingSync Builder
echo ============================================================
echo.

:: ── Check Python ─────────────────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found.
    echo.
    echo Please install Python 3.10 or newer from https://www.python.org/downloads/
    echo Make sure to tick "Add Python to PATH" during installation.
    echo.
    pause
    exit /b 1
)

for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do set PYVER=%%v
echo Python found: %PYVER%

:: ── Install dependencies ──────────────────────────────────────────────────────
echo.
echo Installing required packages (lupa, pyinstaller)...
echo This may take a minute on first run.
echo.

python -m pip install --upgrade pip --quiet
if errorlevel 1 (
    echo [ERROR] pip upgrade failed. Check your internet connection.
    pause
    exit /b 1
)

python -m pip install lupa pyinstaller --quiet
if errorlevel 1 (
    echo [ERROR] Failed to install packages.
    echo Try running this .bat as Administrator, or check your internet connection.
    pause
    exit /b 1
)

echo Packages ready.

:: ── Build exe ────────────────────────────────────────────────────────────────
echo.
echo Building CraftingSync.exe...
echo.

python -m PyInstaller ^
    --onefile ^
    --console ^
    --name CraftingSync ^
    --hidden-import lupa ^
    --hidden-import lupa._lupa ^
    --collect-all lupa ^
    CraftingSync.py

if errorlevel 1 (
    echo.
    echo [ERROR] PyInstaller build failed. See output above for details.
    pause
    exit /b 1
)

:: ── Copy output to dist folder ────────────────────────────────────────────────
echo.
echo Build complete.

if not exist "dist\CraftingSync.exe" (
    echo [ERROR] Expected dist\CraftingSync.exe not found.
    pause
    exit /b 1
)

:: Copy config template next to the exe if not already there
if not exist "dist\config.json" (
    copy /y "config.json" "dist\config.json" >nul
    echo Copied config.json to dist\
)

:: Clean up PyInstaller temp files
if exist "build" rmdir /s /q "build"
if exist "CraftingSync.spec" del /q "CraftingSync.spec"

echo.
echo ============================================================
echo   Done! Your files are in the "dist" folder:
echo.
echo     dist\CraftingSync.exe   ^<-- share this
echo     dist\config.json        ^<-- user edits this once
echo.
echo   Steps for the end user:
echo     1. Put both files in the same folder anywhere on their PC
echo     2. Edit config.json with their WoW path + account SV paths
echo     3. Double-click CraftingSync.exe instead of WoW from now on
echo ============================================================
echo.
pause
