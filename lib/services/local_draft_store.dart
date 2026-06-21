import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/draft.dart';
import '../storage/app_database.dart';

typedef LocalDraftBoxFactory = Future<Box<Map>> Function();

class LocalDraftEntry {
  const LocalDraftEntry({
    required this.data,
    required this.sequence,
    required this.updatedAt,
  });

  final DraftData data;
  final int sequence;
  final DateTime updatedAt;
}

/// 尚未被服务端确认的草稿本地副本。
class LocalDraftStore {
  LocalDraftStore({
    LocalDraftBoxFactory? boxFactory,
    DateTime Function()? now,
    this.retention = const Duration(days: 30),
  }) : _boxFactory =
           boxFactory ?? (() => AppDatabase.namedBox(_defaultBoxName)),
       _now = now ?? DateTime.now;

  static const String _defaultBoxName = 'local_drafts';
  static const String _dataKey = 'data';
  static const String _sequenceKey = 'sequence';
  static const String _updatedAtKey = 'updated_at';

  final LocalDraftBoxFactory _boxFactory;
  final DateTime Function() _now;
  final Duration retention;

  Future<LocalDraftEntry?> read(String accountId, String draftKey) async {
    final box = await _boxFactory();
    await _pruneExpired(box);
    final raw = box.get(_entryKey(accountId, draftKey));
    if (raw == null) return null;

    try {
      final encodedData = raw[_dataKey] as String;
      return LocalDraftEntry(
        data: DraftData.fromJson(
          jsonDecode(encodedData) as Map<String, dynamic>,
        ),
        sequence: (raw[_sequenceKey] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(raw[_updatedAtKey] as String),
      );
    } catch (_) {
      await box.delete(_entryKey(accountId, draftKey));
      return null;
    }
  }

  Future<void> write({
    required String accountId,
    required String draftKey,
    required DraftData data,
    required int sequence,
  }) async {
    final box = await _boxFactory();
    await _pruneExpired(box);
    await box.put(_entryKey(accountId, draftKey), {
      _dataKey: data.toJsonString(),
      _sequenceKey: sequence,
      _updatedAtKey: _now().toUtc().toIso8601String(),
    });
  }

  /// 只删除服务端刚确认的那个版本，避免旧请求误删后续输入。
  Future<bool> deleteIfMatches({
    required String accountId,
    required String draftKey,
    required DraftData data,
  }) async {
    final box = await _boxFactory();
    final key = _entryKey(accountId, draftKey);
    final raw = box.get(key);
    if (raw?[_dataKey] != data.toJsonString()) return false;
    await box.delete(key);
    return true;
  }

  Future<void> delete(String accountId, String draftKey) async {
    final box = await _boxFactory();
    await box.delete(_entryKey(accountId, draftKey));
  }

  Future<void> _pruneExpired(Box<Map> box) async {
    final cutoff = _now().toUtc().subtract(retention);
    final expiredKeys = <dynamic>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      final updatedAtRaw = raw?[_updatedAtKey] as String?;
      final updatedAt = updatedAtRaw == null
          ? null
          : DateTime.tryParse(updatedAtRaw)?.toUtc();
      if (updatedAt == null || updatedAt.isBefore(cutoff)) {
        expiredKeys.add(key);
      }
    }
    if (expiredKeys.isNotEmpty) await box.deleteAll(expiredKeys);
  }

  String _entryKey(String accountId, String draftKey) {
    return jsonEncode([accountId, draftKey]);
  }
}
