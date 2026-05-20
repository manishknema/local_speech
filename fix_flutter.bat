@echo off
set FLUTTER_DIR=%1
if "%FLUTTER_DIR%"=="" (
  echo Usage: fix_flutter.bat <flutter_install_path>
  exit /b 1
)

cd %FLUTTER_DIR%
git remote remove origin
git remote add origin https://github.com/flutter/flutter.git
git fetch origin --tags --force
git reset --hard origin/stable

del /f /q bin\cache\.repository_info
rmdir /s /q bin\cache

flutter doctor
flutter upgrade