#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path


def resolve_plugin_target(source_tree_root: Path, plugin_path: str) -> Path:
    pub_cache_marker = "/.pub-cache/"
    packages_marker = "/packages/"

    if pub_cache_marker in plugin_path:
        suffix = plugin_path.split(pub_cache_marker, 1)[1]
        return source_tree_root / ".pub-cache" / suffix

    if packages_marker in plugin_path:
        suffix = plugin_path.split(packages_marker, 1)[1]
        return source_tree_root / "packages" / suffix

    raise SystemExit(f"unsupported linux plugin path outside staged tree: {plugin_path}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: rebuild_linux_plugin_symlinks.py <source-tree-root>", file=sys.stderr)
        return 1

    source_tree_root = Path(sys.argv[1]).resolve()
    plugin_file = source_tree_root / ".flutter-plugins-dependencies"
    symlink_dir = source_tree_root / "linux" / "flutter" / "ephemeral" / ".plugin_symlinks"

    if not plugin_file.is_file():
        raise SystemExit(f"missing plugin metadata: {plugin_file}")

    data = json.loads(plugin_file.read_text(encoding="utf-8"))
    linux_plugins = data.get("plugins", {}).get("linux", [])

    if symlink_dir.exists():
        shutil.rmtree(symlink_dir)
    symlink_dir.mkdir(parents=True, exist_ok=True)

    for plugin in linux_plugins:
        name = plugin["name"]
        target = resolve_plugin_target(source_tree_root, plugin["path"]).resolve()
        if not target.exists():
            raise SystemExit(f"linux plugin target does not exist for {name}: {target}")

        link_path = symlink_dir / name
        relative_target = os.path.relpath(target, symlink_dir)
        os.symlink(relative_target, link_path)

    print(f"rebuilt {len(linux_plugins)} linux plugin symlink(s) in {symlink_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
