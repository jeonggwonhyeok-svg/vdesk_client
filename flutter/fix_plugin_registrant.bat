@echo off
REM flutter pub get 후 실행하여 flutter_inappwebview_windows 충돌 해결
powershell -ExecutionPolicy Bypass -File "%~dp0fix_plugin_registrant.ps1"
pause
