@echo off
REM Needs Flutter (flutter doctor OK) and Python. Output: build\app\outputs\flutter-apk\app-release.apk
python tools\setup_android.py || goto :err
flutter build apk --release || goto :err
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
pause & exit /b
:err
echo BUILD FAILED & pause
