@echo off
REM One-click build of the Windows installer. Needs Python 3 and Node.js installed.
py -m pip install -q flask segno pyinstaller || goto :err
py -m PyInstaller --noconfirm --onefile --noconsole --name perixa-server --add-data "templates;templates" --add-data "static;static" app.py || goto :err
call npm install || goto :err
call npm run dist || goto :err
echo.
echo Done. Installer is in the "release" folder.
pause & exit /b
:err
echo BUILD FAILED & pause
