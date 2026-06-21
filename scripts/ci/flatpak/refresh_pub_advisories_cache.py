#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


_CACHE_FRESHNESS_MARGIN = timedelta(seconds=5)


def _parse_timestamp(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw:
        return None

    normalized = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _format_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: refresh_pub_advisories_cache.py <pub-cache-dir>", file=sys.stderr)
        return 1

    pub_cache_dir = Path(sys.argv[1]).resolve()
    advisories_dir = pub_cache_dir / "hosted" / "pub.dev" / ".cache"

    if not advisories_dir.is_dir():
        print(f"no advisory cache directory found at {advisories_dir}")
        return 0

    refreshed = 0
    now = datetime.now(timezone.utc)

    # Dart/Flutter may still try to contact pub.dev for package advisories during
    # offline resolution when the per-package advisories cache file is missing.
    # Populate an empty advisories cache for every cached versions file so
    # `pub get --offline` remains truly offline inside Flatpak builds.
    for versions_file in sorted(advisories_dir.glob("*-versions.json")):
        package_name = versions_file.name.removesuffix("-versions.json")
        advisory_file = advisories_dir / f"{package_name}-advisories.json"
        try:
            versions_payload = json.loads(versions_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid versions cache JSON: {versions_file}: {exc}") from exc

        target_timestamp = max(
            now,
            _parse_timestamp(versions_payload.get("advisoriesUpdated")) or now,
            datetime.fromtimestamp(versions_file.stat().st_mtime, tz=timezone.utc),
        ) + _CACHE_FRESHNESS_MARGIN

        if advisory_file.exists():
            try:
                payload = json.loads(advisory_file.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"invalid advisory cache JSON: {advisory_file}: {exc}") from exc
        else:
            payload = {"advisories": []}

        if not isinstance(payload, dict):
            payload = {"advisories": []}

        if not isinstance(payload.get("advisories"), list):
            payload["advisories"] = []

        payload["advisoriesUpdated"] = _format_timestamp(target_timestamp)
        advisory_file.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        touch_timestamp = target_timestamp.timestamp()
        os.utime(advisory_file, (touch_timestamp, touch_timestamp))
        refreshed += 1

    print(f"refreshed {refreshed} pub advisory cache file(s) in {advisories_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
