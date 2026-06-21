# Project Guidelines

## Language

Use Chinese for all communication and code comments.

## Dependencies

When adding or updating dependencies in `pubspec.yaml`:

- **MUST** use the latest stable version of any package.
- **MUST** check [pub.dev](https://pub.dev) for the current version before adding a dependency.
- **NEVER** copy outdated version numbers from memory or examples.

## Time Handling

All time strings from the Discourse API are in UTC format. The project uses a unified `TimeUtils` class (`lib/utils/time_utils.dart`) for all time parsing and formatting.

### Rules

- **MUST** use `TimeUtils.parseUtcTime()` to parse any time string from the API. It handles UTC-to-local conversion internally.
- **MUST** use `TimeUtils.formatRelativeTime()` / `formatDetailTime()` / `formatCompactTime()` / `formatShortDate()` / `formatFullDate()` for display.
- **NEVER** use `DateTime.parse()` or `DateTime.tryParse()` directly in model or UI code.
- **NEVER** call `.toLocal()` outside of `TimeUtils`.

### Correct

```dart
createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
```

### Wrong

```dart
createdAt: DateTime.parse(json['created_at'] as String),
createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
```
