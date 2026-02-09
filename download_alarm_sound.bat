@echo off
REM TaskRelay - Download Free Alarm Sound
REM This script downloads a free alarm sound from Pixabay

echo ========================================
echo TaskRelay - Alarm Sound Downloader
echo ========================================
echo.
echo This will download a free alarm sound and place it in the correct directory.
echo.
pause

set "RAW_DIR=%~dp0android\app\src\main\res\raw"
set "SOUND_FILE=%RAW_DIR%\alarm_sound.mp3"

echo Checking directory...
if not exist "%RAW_DIR%" (
    echo Creating raw directory...
    mkdir "%RAW_DIR%"
)

echo.
echo Downloading alarm sound...
echo.
echo NOTE: This requires curl (available in Windows 10/11)
echo Source: Free sound from Pixabay (CC0 License)
echo.

REM This is a placeholder - user needs to download manually
echo Please download an alarm sound manually from:
echo https://pixabay.com/sound-effects/search/alarm/
echo.
echo 1. Download an alarm sound (MP3 format)
echo 2. Save it as: alarm_sound.mp3
echo 3. Place it in: %RAW_DIR%
echo.
echo Or use this PowerShell command to download a free alarm:
echo.
echo powershell -Command "Invoke-WebRequest -Uri 'https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3' -OutFile '%SOUND_FILE%'"
echo.
pause

REM Uncomment the line below if you want automatic download (requires internet)
REM powershell -Command "Invoke-WebRequest -Uri 'https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3' -OutFile '%SOUND_FILE%'"

echo.
echo After adding the alarm sound:
echo 1. Run: flutter clean
echo 2. Run: flutter build apk (or flutter run)
echo.
pause
