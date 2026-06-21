import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_ce/hive.dart';

import '../storage/app_database.dart';

/// 基于 hive_ce 的 [CacheInfoRepository] 实现。
///
/// 替换 [JsonCacheInfoRepository]。后者有两个致命问题,在缓存上限调到
/// 15000/20000 条后成为表情面板卡顿与图片加载慢的系统性根因:
///
/// 1. `get()` 对全部条目做 `firstWhereOrNull` 线性扫描 —— 每加载一张图
///    都要在主 isolate 扫一遍上万条记录;
/// 2. 任何写入(包括 flutter_cache_manager 每次**读**缓存都会回写 touched
///    时间戳)都会在 3 秒后于主 isolate 上 `jsonEncode` **全部**条目并重写
///    整个文件,几 MB 的同步序列化 → 周期性长帧。
///
/// Hive 普通 box 全量驻内存(2 万条 CacheObject 约几 MB):`get` 是一次
/// Map 查找,`put` 是单条二进制 append,没有全量重写。另做两个针对性优化:
///
/// - **touch 节流**:对"只有 touched 变了"的更新做 [_touchPersistInterval]
///   节流。LRU 淘汰精度损失可忽略(stalePeriod 是 7~90 天),磁盘写入量
///   降约两个数量级;
/// - **放宽 compaction**:覆盖写会在 Hive 文件留垃圾帧,默认 >50 帧就全
///   文件重写,对本场景太激进;放宽到 >1000(垃圾帧约几百 KB,且重写是
///   二进制顺序写,远比 jsonEncode 便宜)。
///
/// 首次 open 时自动把旧的 `{databaseName}.json`(JsonCacheInfoRepository
/// 数据)一次性迁入 box 并删除源文件,sticker 缩略图 PNG 等已有缓存条目
/// 无损保留,不触发重新下载/重新解码。
class HiveCacheInfoRepository implements CacheInfoRepository {
  HiveCacheInfoRepository({
    required this.databaseName,
    @visibleForTesting JsonCacheInfoRepository? legacyRepository,
  }) : _legacyRepository = legacyRepository;

  final String databaseName;

  /// 测试注入用:迁移源仓库。生产路径按 [databaseName] 定位旧 JSON 文件。
  final JsonCacheInfoRepository? _legacyRepository;

  /// 纯 touch 更新的最小落盘间隔。
  static const Duration _touchPersistInterval = Duration(hours: 1);

  Box<Map>? _box;

  /// CacheInfoRepository 契约按 int id 删除,而 box 按 key 存取,这里维护映射。
  final Map<int, String> _idToKey = {};
  int _nextId = 1;

  /// 连接计数(与上游 CacheInfoRepositoryHelperMethods 等价,该 mixin 未导出)。
  int _openConnections = 0;
  Completer<bool>? _openCompleter;

  String get _boxName => 'image_cache_meta_$databaseName';

  // ==================== 生命周期 ====================

  @override
  Future<bool> open() async {
    _openConnections++;
    final existing = _openCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<bool>();
    _openCompleter = completer;
    try {
      _box = await AppDatabase.namedBox(
        _boxName,
        compactionStrategy: (entries, deleted) => deleted > 1000,
      );
      _rebuildIdIndex();
      await _migrateFromJsonRepository();
      completer.complete(true);
    } catch (e, st) {
      completer.completeError(e, st);
    }
    return completer.future;
  }

  @override
  Future<bool> close() async {
    _openConnections--;
    if (_openConnections > 0) return false;
    _openCompleter = null;
    await _box?.close();
    _box = null;
    return true;
  }

  @override
  Future<bool> exists() async {
    final box = _box;
    if (box != null && box.isOpen) return box.isNotEmpty;
    return (await AppDatabase.namedBox(_boxName)).isNotEmpty;
  }

  @override
  Future<void> deleteDataFile() async {
    _idToKey.clear();
    _nextId = 1;
    final box = _box ?? await AppDatabase.namedBox(_boxName);
    await box.clear();
  }

  // ==================== 读写 ====================

  @override
  Future<CacheObject?> get(String key) async {
    final raw = _box!.get(key);
    if (raw == null) return null;
    return CacheObject.fromMap(Map<String, dynamic>.from(raw));
  }

  @override
  Future<List<CacheObject>> getAllObjects() async {
    return _box!.values
        .map((raw) => CacheObject.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  @override
  Future<CacheObject> insert(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async {
    if (cacheObject.id != null) {
      throw ArgumentError("Inserted objects shouldn't have an existing id.");
    }
    final id = _nextId++;
    final map = cacheObject.copyWith(id: id).toMap(
          setTouchedToNow: setTouchedToNow,
        );
    _idToKey[id] = cacheObject.key;
    await _box!.put(cacheObject.key, map);
    return CacheObject.fromMap(map);
  }

  @override
  Future<int> update(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async {
    if (cacheObject.id == null) {
      throw ArgumentError('Updated objects should have an existing id.');
    }
    final map = cacheObject.toMap(setTouchedToNow: setTouchedToNow);
    if (_isThrottledTouch(cacheObject.key, map)) return 1;
    _idToKey[cacheObject.id!] = cacheObject.key;
    await _box!.put(cacheObject.key, map);
    return 1;
  }

  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) {
    return cacheObject.id == null
        ? insert(cacheObject)
        : update(cacheObject);
  }

  /// 是否为可跳过的纯 touch 更新:除 touched 外所有字段与磁盘一致,
  /// 且距上次落盘的 touched 不足 [_touchPersistInterval]。
  bool _isThrottledTouch(String key, Map<String, dynamic> newMap) {
    final raw = _box!.get(key);
    if (raw == null) return false;
    for (final col in const [
      CacheObject.columnId,
      CacheObject.columnUrl,
      CacheObject.columnKey,
      CacheObject.columnPath,
      CacheObject.columnETag,
      CacheObject.columnValidTill,
      CacheObject.columnLength,
    ]) {
      if (raw[col] != newMap[col]) return false;
    }
    final lastTouched = raw[CacheObject.columnTouched] as int? ?? 0;
    final newTouched = newMap[CacheObject.columnTouched] as int? ?? 0;
    return newTouched - lastTouched < _touchPersistInterval.inMilliseconds;
  }

  // ==================== 清理 ====================

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async {
    final allSorted = await getAllObjects()
      ..sort((a, b) => a.touched!.compareTo(b.touched!));
    if (allSorted.length <= capacity) return [];
    return allSorted.getRange(0, allSorted.length - capacity).toList();
  }

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async {
    final oldest = DateTime.now().subtract(maxAge);
    return (await getAllObjects())
        .where((obj) => obj.touched!.isBefore(oldest))
        .toList();
  }

  @override
  Future<int> delete(int id) async {
    final key = _idToKey.remove(id);
    if (key == null) return 0;
    await _box!.delete(key);
    return 1;
  }

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    final keys = <String>[];
    for (final id in ids) {
      final key = _idToKey.remove(id);
      if (key != null) keys.add(key);
    }
    await _box!.deleteAll(keys);
    return keys.length;
  }

  // ==================== 内部 ====================

  void _rebuildIdIndex() {
    _idToKey.clear();
    var maxId = 0;
    final box = _box!;
    for (final key in box.keys) {
      final raw = box.get(key);
      final id = raw?[CacheObject.columnId] as int?;
      if (id == null) continue;
      _idToKey[id] = key as String;
      if (id > maxId) maxId = id;
    }
    _nextId = maxId + 1;
  }

  /// 把旧 JsonCacheInfoRepository 的 `{databaseName}.json` 一次性迁入 box。
  ///
  /// 用 `putAll` 单批写入(逐条 put 上万次 append 会拖慢首次启动);
  /// 迁移完删除 JSON 源文件,之后这段逻辑只剩一次 `exists()` 开销。
  Future<void> _migrateFromJsonRepository() async {
    try {
      final legacy =
          _legacyRepository ?? JsonCacheInfoRepository(databaseName: databaseName);
      if (!await legacy.exists()) return;
      await legacy.open();
      final objects = await legacy.getAllObjects();
      final entries = <String, Map<String, dynamic>>{};
      for (final obj in objects) {
        if (_box!.containsKey(obj.key)) continue;
        var id = obj.id;
        if (id == null || _idToKey.containsKey(id)) {
          id = _nextId++;
        }
        final map = obj.copyWith(id: id).toMap(setTouchedToNow: false);
        _idToKey[id] = obj.key;
        entries[obj.key] = map;
      }
      if (entries.isNotEmpty) {
        await _box!.putAll(entries);
        _rebuildIdIndex();
      }
      await legacy.deleteDataFile();
      debugPrint(
        '[HiveCacheInfoRepository] migrated ${entries.length} entries '
        'from $databaseName.json',
      );
    } catch (e) {
      // 迁移失败不阻塞 open —— 最坏情况是旧缓存作废重新下载
      debugPrint('[HiveCacheInfoRepository] migration failed: $e');
    }
  }
}
