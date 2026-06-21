import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Falls back to SharedPreferences when the platform keyring is unavailable.
class ResilientSecureStorage {
  ResilientSecureStorage({
    FlutterSecureStorage? secureStorage,
    String fallbackPrefix = '__secure_fallback__',
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           ),
       _fallbackPrefix = fallbackPrefix;

  final FlutterSecureStorage _secureStorage;
  final String _fallbackPrefix;

  static Future<SharedPreferences>? _prefsFuture;
  bool _secureStorageUnavailable = false;

  Future<String?> read({required String key}) async {
    if (!_secureStorageUnavailable) {
      try {
        final value = await _secureStorage.read(key: key);
        if (value != null) {
          await _removeFallback(key);
          return value;
        }
        final fallbackValue = await _readFallback(key);
        if (fallbackValue != null) {
          await _tryPromoteFallback(key, fallbackValue);
        }
        return fallbackValue;
      } catch (error) {
        _markFallback('read', key, error);
      }
    }
    return _readFallback(key);
  }

  Future<void> write({required String key, required String value}) async {
    if (!_secureStorageUnavailable) {
      try {
        await _secureStorage.write(key: key, value: value);
        await _removeFallback(key);
        return;
      } catch (error) {
        _markFallback('write', key, error);
      }
    }
    await _writeFallback(key, value);
  }

  Future<void> delete({required String key}) async {
    if (!_secureStorageUnavailable) {
      try {
        await _secureStorage.delete(key: key);
      } catch (error) {
        _markFallback('delete', key, error);
      }
    }
    await _removeFallback(key);
  }

  Future<void> _tryPromoteFallback(String key, String value) async {
    if (_secureStorageUnavailable) {
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
      await _removeFallback(key);
    } catch (error) {
      _markFallback('promote', key, error);
    }
  }

  void _markFallback(String operation, String key, Object error) {
    if (!_secureStorageUnavailable) {
      debugPrint(
        '[ResilientSecureStorage] $operation($key) failed, fallback to SharedPreferences: $error',
      );
    }
    _secureStorageUnavailable = true;
  }

  Future<SharedPreferences> get _prefs async {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  String _fallbackKey(String key) => '$_fallbackPrefix$key';

  Future<String?> _readFallback(String key) async {
    final prefs = await _prefs;
    return prefs.getString(_fallbackKey(key));
  }

  Future<void> _writeFallback(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(_fallbackKey(key), value);
  }

  Future<void> _removeFallback(String key) async {
    final prefs = await _prefs;
    await prefs.remove(_fallbackKey(key));
  }
}
