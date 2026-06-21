# enhanced_cookie_jar

An incremental replacement for cookie_jar with richer cookie metadata.

## Goals

- Preserve additional cookie fields such as sameSite, partitionKey, priority, sourceScheme.
- Keep a canonical persisted cookie model instead of relying only on dart:io Cookie.
- Stay compatible with the familiar saveFromResponse / loadForRequest workflow.

## Current scope

- Canonical cookie model
- Set-Cookie header parser
- JSON file store
- Persisted jar compatible with cookie_jar.CookieJar`n+
## Not implemented yet

- Chromium CDP cookie import/export helpers
- Full RFC-level eviction policy
- Partition-aware request selection rules beyond persistence and identity
