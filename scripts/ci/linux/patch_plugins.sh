#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
PATCHED=0

declare -a SEARCH_ROOTS=()

if [[ -d "${PUB_CACHE_DIR}" ]]; then
  SEARCH_ROOTS+=("${PUB_CACHE_DIR}")
fi

if [[ -d "${PROJECT_ROOT}/.pub-cache" ]]; then
  SEARCH_ROOTS+=("${PROJECT_ROOT}/.pub-cache")
fi

if [[ "${#SEARCH_ROOTS[@]}" -eq 0 ]]; then
  echo "==> No pub cache directory found, skipping Linux plugin patches"
  exit 0
fi

mapfile -t JSON_HEADERS < <(find "${SEARCH_ROOTS[@]}" -path '*flutter_secure_storage_linux-*/linux/include/json.hpp' 2>/dev/null | sort -u)

for header in "${JSON_HEADERS[@]}"; do
  if grep -q 'operator "" _json' "${header}"; then
    echo "==> Patching ${header}"
    sed -i \
      -e 's/operator "" _json/operator""_json/g' \
      -e 's/operator "" _json_pointer/operator""_json_pointer/g' \
      "${header}"
    PATCHED=1
  fi
done

mapfile -t CARGOKIT_RUN_BUILD_TOOL_SH < <(find "${SEARCH_ROOTS[@]}" -path '*/cargokit/run_build_tool.sh' 2>/dev/null | sort -u)

for script in "${CARGOKIT_RUN_BUILD_TOOL_SH[@]}"; do
  if grep -q 'pub get --no-precompile' "${script}" && ! grep -q 'pub get --offline --no-precompile' "${script}"; then
    echo "==> Patching ${script}"
    sed -i 's/pub get --no-precompile/pub get --offline --no-precompile/g' "${script}"
    PATCHED=1
  fi
done

mapfile -t CARGOKIT_RUN_BUILD_TOOL_CMD < <(find "${SEARCH_ROOTS[@]}" -path '*/cargokit/run_build_tool.cmd' 2>/dev/null | sort -u)

for script in "${CARGOKIT_RUN_BUILD_TOOL_CMD[@]}"; do
  if grep -q 'pub get --no-precompile' "${script}" && ! grep -q 'pub get --offline --no-precompile' "${script}"; then
    echo "==> Patching ${script}"
    sed -i 's/pub get --no-precompile/pub get --offline --no-precompile/g' "${script}"
    PATCHED=1
  fi
done

if [[ "${PATCHED}" -eq 0 ]]; then
  echo "==> No Linux plugin patches needed"
fi
