#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: list_linux_rust_manifests.py <source-tree-root>", file=sys.stderr)
        return 1

    source_tree_root = Path(sys.argv[1]).resolve()
    plugin_file = source_tree_root / ".flutter-plugins-dependencies"
    if not plugin_file.is_file():
        print(f"missing plugin metadata: {plugin_file}", file=sys.stderr)
        return 1

    data = json.loads(plugin_file.read_text(encoding="utf-8"))
    manifests: list[str] = []
    seen: set[str] = set()

    for plugin in data.get("plugins", {}).get("linux", []):
        if not plugin.get("native_build"):
            continue

        plugin_path = Path(plugin["path"]).resolve()
        manifest_path = plugin_path / "rust" / "Cargo.toml"
        if not manifest_path.is_file():
            continue

        try:
            relative_manifest = manifest_path.relative_to(source_tree_root).as_posix()
        except ValueError as exc:
            raise SystemExit(
                f"plugin manifest is outside staged source tree: {manifest_path}"
            ) from exc

        if relative_manifest not in seen:
            manifests.append(relative_manifest)
            seen.add(relative_manifest)

    for manifest in manifests:
        print(manifest)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
