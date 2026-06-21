#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


VERSION_PATTERN = re.compile(
    r"^version:\s*"
    r"([0-9]+)\.([0-9]+)\.([0-9]+)"
    r"(?:-([0-9A-Za-z.-]+))?"
    r"(?:\+([^\s#]+))?\s*$"
)


def parse_version(pubspec_path: Path) -> tuple[str, int, int, int, int]:
    for line in pubspec_path.read_text(encoding="utf-8").splitlines():
        match = VERSION_PATTERN.match(line.strip())
        if not match:
            continue

        major = int(match.group(1))
        minor = int(match.group(2))
        patch = int(match.group(3))
        prerelease_suffix = match.group(4)
        build_suffix = match.group(5)
        version = f"{major}.{minor}.{patch}"
        if prerelease_suffix:
            version = f"{version}-{prerelease_suffix}"

        build_number = 0
        if build_suffix:
            version = f"{version}+{build_suffix}"
            if build_suffix.isdigit():
                build_number = int(build_suffix)

        return version, major, minor, patch, build_number

    raise SystemExit(f"unable to parse version from {pubspec_path}")


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: write_linux_generated_config.py <project-root> <flutter-root> <target-file> <output-file>",
            file=sys.stderr,
        )
        return 1

    project_root = Path(sys.argv[1]).resolve()
    flutter_root = Path(sys.argv[2]).resolve()
    target_file = Path(sys.argv[3]).as_posix()
    output_file = Path(sys.argv[4]).resolve()

    version, major, minor, patch, build_number = parse_version(project_root / "pubspec.yaml")
    package_config = (project_root / ".dart_tool" / "package_config.json").resolve().as_posix()

    output = f"""# Generated code do not commit.
file(TO_CMAKE_PATH "{flutter_root.as_posix()}" FLUTTER_ROOT)
file(TO_CMAKE_PATH "{project_root.as_posix()}" PROJECT_DIR)

set(FLUTTER_VERSION "{version}" PARENT_SCOPE)
set(FLUTTER_VERSION_MAJOR {major} PARENT_SCOPE)
set(FLUTTER_VERSION_MINOR {minor} PARENT_SCOPE)
set(FLUTTER_VERSION_PATCH {patch} PARENT_SCOPE)
set(FLUTTER_VERSION_BUILD {build_number} PARENT_SCOPE)

# Environment variables to pass to tool_backend.sh
list(APPEND FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_ROOT={flutter_root.as_posix()}"
  "PROJECT_DIR={project_root.as_posix()}"
  "FLUTTER_TARGET={target_file}"
  "DART_OBFUSCATION=false"
  "TRACK_WIDGET_CREATION=false"
  "TREE_SHAKE_ICONS=false"
  "PACKAGE_CONFIG={package_config}"
)
"""

    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(output, encoding="utf-8")
    print(f"wrote {output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
