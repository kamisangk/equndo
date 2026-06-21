#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import quote, unquote, urlparse


PUB_CACHE_MARKERS = (
    "/.pub-cache/",
    "/Pub/Cache/",
    "/pub-cache/",
)


def _as_file_uri(path: Path) -> str:
    posix_path = path.resolve().as_posix()
    return f"file://{quote(posix_path, safe='/._-~')}"


def _normalize_path(raw_path: str) -> str:
    return raw_path.replace("\\", "/")


def _file_uri_to_normalized_path(raw_uri: object) -> str | None:
    if not isinstance(raw_uri, str):
        return None

    parsed = urlparse(raw_uri)
    if parsed.scheme != "file":
        return None

    return _normalize_path(unquote(parsed.path))


def _relative_posix_suffix(normalized_path: str, normalized_root: str) -> PurePosixPath | None:
    path_value = normalized_path.rstrip("/")
    root_value = normalized_root.rstrip("/")

    if not root_value:
        return None

    if path_value.casefold() == root_value.casefold():
        return PurePosixPath(".")

    root_prefix = f"{root_value}/"
    if path_value.casefold().startswith(root_prefix.casefold()):
        return PurePosixPath(path_value[len(root_prefix) :].lstrip("/"))

    return None


def _relocate_normalized_path(
    raw_path: str,
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> Path | None:
    normalized = _normalize_path(raw_path)

    if original_flutter_root is not None:
        flutter_suffix = _relative_posix_suffix(normalized, original_flutter_root)
        if flutter_suffix is not None:
            return source_tree_root / "flutter-sdk" / flutter_suffix

    if original_pub_cache is not None:
        pub_cache_suffix = _relative_posix_suffix(normalized, original_pub_cache)
        if pub_cache_suffix is not None:
            return source_tree_root / ".pub-cache" / pub_cache_suffix

    for marker in PUB_CACHE_MARKERS:
        if marker not in normalized:
            continue

        suffix = normalized.split(marker, 1)[1].lstrip("/")
        return source_tree_root / ".pub-cache" / PurePosixPath(suffix)

    if "/packages/" in normalized:
        suffix = normalized.split("/packages/", 1)[1].lstrip("/")
        candidate = source_tree_root / "packages" / PurePosixPath(suffix)
        if candidate.exists():
            return candidate

    return None


def _rewrite_file_uri(
    raw_uri: object,
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> object:
    if not isinstance(raw_uri, str):
        return raw_uri

    normalized_path = _file_uri_to_normalized_path(raw_uri)
    if normalized_path is None:
        return raw_uri

    relocated = _relocate_normalized_path(
        normalized_path,
        source_tree_root,
        original_flutter_root=original_flutter_root,
        original_pub_cache=original_pub_cache,
    )
    if relocated is not None:
        return _as_file_uri(relocated)

    return raw_uri


def _rewrite_plugin_path(
    raw_path: object,
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> object:
    if not isinstance(raw_path, str):
        return raw_path

    relocated = _relocate_normalized_path(
        raw_path,
        source_tree_root,
        original_flutter_root=original_flutter_root,
        original_pub_cache=original_pub_cache,
    )
    if relocated is not None:
        return relocated.resolve().as_posix()

    return raw_path


def _load_original_roots(package_config_payload: dict[str, object]) -> tuple[str | None, str | None]:
    return (
        _file_uri_to_normalized_path(package_config_payload.get("flutterRoot")),
        _file_uri_to_normalized_path(package_config_payload.get("pubCache")),
    )


def _rewrite_package_config(
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> int:
    package_config_path = source_tree_root / ".dart_tool" / "package_config.json"
    if not package_config_path.is_file():
        raise SystemExit(f"missing package config: {package_config_path}")

    payload = json.loads(package_config_path.read_text(encoding="utf-8"))
    packages = payload.get("packages", [])
    rewritten = 0

    if isinstance(packages, list):
        for package in packages:
            if isinstance(package, dict):
                original = package.get("rootUri")
                updated = _rewrite_file_uri(
                    original,
                    source_tree_root,
                    original_flutter_root=original_flutter_root,
                    original_pub_cache=original_pub_cache,
                )
                if updated != original:
                    package["rootUri"] = updated
                    rewritten += 1

    payload["generator"] = "fluxdo-flatpak"
    payload["flutterRoot"] = _as_file_uri(source_tree_root / "flutter-sdk")
    payload["pubCache"] = _as_file_uri(source_tree_root / ".pub-cache")

    package_config_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return rewritten


def _rewrite_flutter_plugins_dependencies(
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> int:
    plugin_file = source_tree_root / ".flutter-plugins-dependencies"
    if not plugin_file.is_file():
        return 0

    payload = json.loads(plugin_file.read_text(encoding="utf-8"))
    rewritten = 0

    plugins = payload.get("plugins", {})
    if isinstance(plugins, dict):
        for platform_plugins in plugins.values():
            if not isinstance(platform_plugins, list):
                continue
            for plugin in platform_plugins:
                if not isinstance(plugin, dict):
                    continue
                original = plugin.get("path")
                updated = _rewrite_plugin_path(
                    original,
                    source_tree_root,
                    original_flutter_root=original_flutter_root,
                    original_pub_cache=original_pub_cache,
                )
                if updated != original:
                    plugin["path"] = updated
                    rewritten += 1

    plugin_file.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    return rewritten


def _rewrite_extension_discovery(
    source_tree_root: Path,
    *,
    original_flutter_root: str | None,
    original_pub_cache: str | None,
) -> int:
    discovery_dir = source_tree_root / ".dart_tool" / "extension_discovery"
    if not discovery_dir.is_dir():
        return 0

    rewritten = 0

    for discovery_file in sorted(discovery_dir.glob("*.json")):
        payload = json.loads(discovery_file.read_text(encoding="utf-8"))
        entries = payload.get("entries", [])
        if not isinstance(entries, list):
            continue

        file_rewritten = False
        for entry in entries:
            if not isinstance(entry, dict):
                continue

            original = entry.get("rootUri")
            updated = _rewrite_file_uri(
                original,
                source_tree_root,
                original_flutter_root=original_flutter_root,
                original_pub_cache=original_pub_cache,
            )
            if updated != original:
                entry["rootUri"] = updated
                rewritten += 1
                file_rewritten = True

        if file_rewritten:
            discovery_file.write_text(
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )

    return rewritten


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: relocate_staged_pub_metadata.py <source-tree-root>", file=sys.stderr)
        return 1

    source_tree_root = Path(sys.argv[1]).resolve()
    package_config_path = source_tree_root / ".dart_tool" / "package_config.json"
    if not package_config_path.is_file():
        raise SystemExit(f"missing package config: {package_config_path}")

    package_config_payload = json.loads(package_config_path.read_text(encoding="utf-8"))
    original_flutter_root, original_pub_cache = _load_original_roots(package_config_payload)

    package_count = _rewrite_package_config(
        source_tree_root,
        original_flutter_root=original_flutter_root,
        original_pub_cache=original_pub_cache,
    )
    plugin_count = _rewrite_flutter_plugins_dependencies(
        source_tree_root,
        original_flutter_root=original_flutter_root,
        original_pub_cache=original_pub_cache,
    )
    extension_count = _rewrite_extension_discovery(
        source_tree_root,
        original_flutter_root=original_flutter_root,
        original_pub_cache=original_pub_cache,
    )
    print(
        "relocated staged pub metadata in "
        f"{source_tree_root} ({package_count} package config entries, "
        f"{plugin_count} plugin paths, {extension_count} extension entries)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
