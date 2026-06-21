#!/usr/bin/env bash

set -euo pipefail

BUILD_ROOT="${1:-}"
OUTPUT_ARCHIVE="${2:-}"

if [[ -z "${BUILD_ROOT}" || -z "${OUTPUT_ARCHIVE}" ]]; then
  echo "Usage: $0 <flatpak-build-root> <output-archive>" >&2
  exit 1
fi

FILES_DIR="${BUILD_ROOT}/files"

if [[ ! -d "${FILES_DIR}" ]]; then
  echo "Missing Flatpak files directory: ${FILES_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_ARCHIVE}")"
rm -f "${OUTPUT_ARCHIVE}" "${OUTPUT_ARCHIVE}.sha256"

tar -C "${FILES_DIR}" -caf "${OUTPUT_ARCHIVE}" .
(
  cd "$(dirname "${OUTPUT_ARCHIVE}")"
  sha256sum "$(basename "${OUTPUT_ARCHIVE}")" > "$(basename "${OUTPUT_ARCHIVE}").sha256"
)
