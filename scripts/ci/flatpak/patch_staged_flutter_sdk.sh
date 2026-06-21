#!/usr/bin/env bash

set -euo pipefail

SOURCE_TREE_ROOT="${1:-}"

if [[ -z "${SOURCE_TREE_ROOT}" || ! -d "${SOURCE_TREE_ROOT}" ]]; then
  echo "Usage: $0 <source-tree-root>" >&2
  exit 1
fi

STAGED_FLUTTER_ROOT="${SOURCE_TREE_ROOT}/flutter-sdk"
STAGED_FLUTTER_WRAPPER="${STAGED_FLUTTER_ROOT}/bin/flutter"
STAGED_TOOL_BACKEND="${STAGED_FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.dart"
STAGED_TOOLS_PACKAGE_CONFIG="${STAGED_FLUTTER_ROOT}/packages/flutter_tools/.dart_tool/package_config.json"

if [[ ! -d "${STAGED_FLUTTER_ROOT}" ]]; then
  echo "missing staged Flutter SDK: ${STAGED_FLUTTER_ROOT}" >&2
  exit 1
fi

echo "==> Patching staged Flutter SDK wrapper for offline Flatpak builds"

cat > "${STAGED_FLUTTER_WRAPPER}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

unset CDPATH

if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  SDK_ROOT="${FLUTTER_ROOT}"
else
  PROG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  SDK_ROOT="$(cd "${PROG_DIR}/.." && pwd -P)"
fi

DART_BIN="${SDK_ROOT}/bin/cache/dart-sdk/bin/dart"
TOOLS_PACKAGE_CONFIG="${SDK_ROOT}/packages/flutter_tools/.dart_tool/package_config.json"
TOOLS_SNAPSHOT="${SDK_ROOT}/bin/cache/flutter_tools.snapshot"

exec "${DART_BIN}" \
  --packages="${TOOLS_PACKAGE_CONFIG}" \
  "${TOOLS_SNAPSHOT}" \
  --suppress-analytics \
  --no-version-check \
  "$@"
EOF

chmod 755 "${STAGED_FLUTTER_WRAPPER}"

if [[ ! -f "${STAGED_TOOL_BACKEND}" ]]; then
  echo "missing staged Flutter tool backend: ${STAGED_TOOL_BACKEND}" >&2
  exit 1
fi

if [[ ! -f "${STAGED_TOOLS_PACKAGE_CONFIG}" ]]; then
  echo "missing staged Flutter tools package config: ${STAGED_TOOLS_PACKAGE_CONFIG}" >&2
  exit 1
fi

python3 - "${SOURCE_TREE_ROOT}" "${STAGED_TOOLS_PACKAGE_CONFIG}" "${STAGED_TOOL_BACKEND}" <<'PY'
from pathlib import Path, PurePosixPath
from urllib.parse import quote, unquote, urlparse
import json
import sys

source_tree_root = Path(sys.argv[1]).resolve()
tools_package_config = Path(sys.argv[2])
tool_backend = Path(sys.argv[3])


def as_file_uri(path: Path) -> str:
    posix_path = path.resolve().as_posix()
    return f"file://{quote(posix_path, safe='/._-~')}"


def relocate_pub_cache_uri(raw_uri: object) -> object:
    if not isinstance(raw_uri, str):
        return raw_uri

    parsed = urlparse(raw_uri)
    if parsed.scheme != "file":
        return raw_uri

    normalized = unquote(parsed.path).replace("\\", "/")
    for marker in ("/.pub-cache/", "/Pub/Cache/", "/pub-cache/"):
        if marker not in normalized:
            continue

        suffix = normalized.split(marker, 1)[1].lstrip("/")
        return as_file_uri(source_tree_root / ".pub-cache" / PurePosixPath(suffix))

    return raw_uri


package_payload = json.loads(tools_package_config.read_text(encoding="utf-8"))
packages = package_payload.get("packages", [])
if isinstance(packages, list):
    for package in packages:
        if not isinstance(package, dict):
            continue
        original_root = package.get("rootUri")
        updated_root = relocate_pub_cache_uri(original_root)
        if updated_root != original_root:
            package["rootUri"] = updated_root

package_payload["pubCache"] = as_file_uri(source_tree_root / ".pub-cache")
tools_package_config.write_text(
    json.dumps(package_payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

contents = tool_backend.read_text(encoding="utf-8")

project_marker = "  final String? projectDirectory = Platform.environment['PROJECT_DIR'];\n"
package_config_snippet = (
    "  final String? projectDirectory = Platform.environment['PROJECT_DIR'];\n"
    "  final String? packageConfigPath = Platform.environment['PACKAGE_CONFIG'];\n"
)
if "packageConfigPath = Platform.environment['PACKAGE_CONFIG']" not in contents:
    if project_marker not in contents:
        raise SystemExit(f"failed to locate project directory marker in {tool_backend}")
    contents = contents.replace(project_marker, package_config_snippet, 1)

assemble_marker = "  final Process assembleProcess = await Process.start(flutterExecutable, <String>[\n"
assemble_insertions = []
if "--packages=$packageConfigPath" not in contents:
    assemble_insertions.append(
        "    if (packageConfigPath != null && packageConfigPath.isNotEmpty) '--packages=$packageConfigPath',\n"
    )
if assemble_insertions:
    if assemble_marker not in contents:
        raise SystemExit(f"failed to locate assemble process marker in {tool_backend}")
    contents = contents.replace(assemble_marker, assemble_marker + "".join(assemble_insertions), 1)

tool_backend.write_text(contents, encoding="utf-8")
PY
