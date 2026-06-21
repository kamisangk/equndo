#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${1:-}"

if [[ -z "${BUNDLE_DIR}" || ! -d "${BUNDLE_DIR}" ]]; then
  echo "Usage: $0 <bundle-dir>" >&2
  exit 1
fi

BUNDLE_LIB_DIR="${BUNDLE_DIR}/lib"
PLUGIN_LIB="${BUNDLE_LIB_DIR}/libflutter_inappwebview_linux_plugin.so"
BUNDLE_REALPATH="$(cd "${BUNDLE_DIR}" && pwd)"

if [[ ! -f "${PLUGIN_LIB}" ]]; then
  echo "No flutter_inappwebview Linux plugin found at ${PLUGIN_LIB}, skipping WPE bundling"
  exit 0
fi

declare -A SEEN=()
declare -a QUEUE=("${PLUGIN_LIB}")

should_skip_dependency() {
  local base_name="$1"

  # Skip glibc / loader.
  [[ "${base_name}" =~ ^(linux-vdso|ld-linux|ld-musl) ]] && return 0
  [[ "${base_name}" =~ ^lib(c|m|dl|pthread|rt|util|resolv|nsl|anl)\.so ]] && return 0

  # Skip libraries that should come from the Flatpak runtime / graphics stack.
  [[ "${base_name}" =~ ^lib(gio|glib|gobject|gmodule|gthread)-2\.0\.so ]] && return 0
  [[ "${base_name}" =~ ^lib(gtk-3|gdk-3|atk-1\.0|atspi|pango|pangocairo|pangoft2|cairo|cairo-gobject|harfbuzz|freetype|fontconfig|fribidi|pixman-1|epoxy|secret-1)\.so ]] && return 0
  [[ "${base_name}" =~ ^lib(X11|Xau|Xcomposite|Xcursor|Xdamage|Xdmcp|Xext|Xfixes|Xi|Xinerama|Xrandr|Xrender|Xtst|xcb|xkbcommon|wayland|EGL|GLX|GLdispatch|OpenGL|gbm|drm)\.so ]] && return 0
  [[ "${base_name}" =~ ^lib(stdc\+\+|gcc_s)\.so ]] && return 0

  return 1
}

while [[ "${#QUEUE[@]}" -gt 0 ]]; do
  CURRENT="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")

  while read -r resolved_path; do
    [[ -n "${resolved_path}" ]] || continue

    if [[ "${resolved_path}" == "${BUNDLE_REALPATH}"/* ]]; then
      QUEUE+=("${resolved_path}")
      continue
    fi

    base_name="$(basename "${resolved_path}")"

    if should_skip_dependency "${base_name}"; then
      continue
    fi

    if [[ -n "${SEEN[${resolved_path}]:-}" ]]; then
      continue
    fi

    SEEN["${resolved_path}"]=1
    echo "==> Copying ${resolved_path}"
    cp -L -n "${resolved_path}" "${BUNDLE_LIB_DIR}/"
    QUEUE+=("${BUNDLE_LIB_DIR}/${base_name}")
  done < <(
    LD_LIBRARY_PATH="${BUNDLE_LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
      ldd "${CURRENT}" | awk '/=> \// { print $3 }'
  )
done
