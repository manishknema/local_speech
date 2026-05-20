#!/bin/bash
FLUTTER_DIR=$1
if [ -z "$FLUTTER_DIR" ]; then
  echo "Usage: ./fix_flutter.sh <flutter_install_path>"
  exit 1
fi

cd "$FLUTTER_DIR" || exit 1
git remote remove origin
git remote add origin https://github.com/flutter/flutter.git
git fetch origin --tags --force
git reset --hard origin/stable

rm -f bin/cache/.repository_info
rm -rf bin/cache

flutter doctor
flutter upgrade