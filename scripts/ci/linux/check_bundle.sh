#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${1:-}"

if [[ -z "${BUNDLE_DIR}" || ! -d "${BUNDLE_DIR}" ]]; then
  echo "Usage: $0 <bundle-dir>" >&2
  exit 1
fi

REPORT_DIR=".artifacts/linux"
mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/ldd-report.txt"
>"${REPORT_FILE}"
BUNDLE_LIB_DIR="${BUNDLE_DIR}/lib"

mapfile -t CANDIDATES < <(
  {
    find "${BUNDLE_DIR}" -maxdepth 1 -type f -perm -111
    find "${BUNDLE_DIR}/lib" -type f \( -name '*.so' -o -name '*.so.*' \) 2>/dev/null
  } | sort -u
)

if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
  echo "No ELF candidates found under ${BUNDLE_DIR}" >&2
  exit 1
fi

MISSING=0

for candidate in "${CANDIDATES[@]}"; do
  if ! file "${candidate}" | grep -q 'ELF'; then
    continue
  fi

  echo "== ${candidate}" | tee -a "${REPORT_FILE}"
  LD_LIBRARY_PATH="${BUNDLE_LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    ldd "${candidate}" | tee -a "${REPORT_FILE}"
  echo | tee -a "${REPORT_FILE}"

  if LD_LIBRARY_PATH="${BUNDLE_LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
      ldd "${candidate}" | grep -q 'not found'; then
    MISSING=1
  fi
done

if [[ "${MISSING}" -ne 0 ]]; then
  echo "Missing shared libraries detected. See ${REPORT_FILE}" >&2
  exit 1
fi
