#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}" # debug|release

if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 1
fi

find_vcvars() {
  if command -v vswhere.exe >/dev/null 2>&1; then
    local install_path
    install_path="$(vswhere.exe -latest -products '*' -property installationPath | tr -d '\r')"
    if [[ -n "$install_path" && -f "$install_path/VC/Auxiliary/Build/vcvars64.bat" ]]; then
      echo "$install_path/VC/Auxiliary/Build/vcvars64.bat"
      return 0
    fi
  fi

  local candidates=(
    "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files/Microsoft Visual Studio/18/Community/VC/Auxiliary/Build/vcvars64.bat"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done

  return 1
}

VCVARS_PATH="$(find_vcvars || true)"
if [[ -z "${VCVARS_PATH:-}" ]]; then
  echo "Unable to find vcvars64.bat. Install Visual Studio C++ Desktop workload." >&2
  exit 1
fi

echo "[windows-build] Using vcvars: $VCVARS_PATH"
cmd.exe /c "call \"${VCVARS_PATH//\//\\}\" && flutter build windows --${MODE}"

