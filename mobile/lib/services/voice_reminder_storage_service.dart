import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_family_voice_sound_uri.dart';

/// Local cache for PRO family voice clips (per caregiver ↔ elder pair).
class VoiceReminderStorageService {
  VoiceReminderStorageService._();

  static final VoiceReminderStorageService instance =
      VoiceReminderStorageService._();

  static String localFileName({
    required int caregiverUserId,
    required int elderUserId,
  }) =>
      'family_${caregiverUserId}_${elderUserId}_voice.m4a';

  static String _remoteUrlPrefsKey(int caregiverUserId, int elderUserId) =>
      'family_voice_remote_url_${caregiverUserId}_$elderUserId';

  static String _androidUriPrefsKey(int caregiverUserId, int elderUserId) =>
      'family_voice_content_uri_${caregiverUserId}_$elderUserId';

  static String _androidUriPathPrefsKey(int caregiverUserId, int elderUserId) =>
      'family_voice_content_uri_path_${caregiverUserId}_$elderUserId';

  Future<Directory> notificationSoundsDirectory() async {
    try {
      if (Platform.isIOS) {
        final library = await getLibraryDirectory();
        final sounds = Directory('${library.path}/Sounds');
        if (!await sounds.exists()) {
          await sounds.create(recursive: true);
        }
        return sounds;
      }
      final filesRoot = await getApplicationSupportDirectory();
      final voices = Directory('${filesRoot.path}/medication_voices');
      if (!await voices.exists()) {
        await voices.create(recursive: true);
      }
      await _migrateLegacyAndroidVoiceDir(voices);
      return voices;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: failed to resolve sounds dir: $e\n$st');
      }
      rethrow;
    }
  }

  Future<void> _migrateLegacyAndroidVoiceDir(Directory targetDir) async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacyDir = Directory('${docs.path}/medication_voices');
      if (!await legacyDir.exists()) return;
      await for (final entity in legacyDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final dest = File('${targetDir.path}/$name');
        if (!await dest.exists() || await dest.length() == 0) {
          await entity.copy(dest.path);
        }
        final legacyElder = RegExp(r'^family_(\d+)_voice\.m4a$').firstMatch(name);
        if (legacyElder != null) {
          final elderId = int.tryParse(legacyElder.group(1)!);
          if (elderId != null) {
            await _cacheAndroidNotificationContentUri(
              caregiverUserId: elderId,
              elderUserId: elderId,
              path: dest.path,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('voice storage: legacy migrate skipped: $e');
      }
    }
  }

  Future<File> localFileForPair({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    final dir = await notificationSoundsDirectory();
    return File(
      '${dir.path}/${localFileName(caregiverUserId: caregiverUserId, elderUserId: elderUserId)}',
    );
  }

  Future<bool> hasLocalVoiceForPair({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    try {
      final file = await localFileForPair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      return file.existsSync() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Drops cached file + prefs so the next [ensureDownloaded] fetches fresh audio.
  Future<void> invalidatePair({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    try {
      final file = await localFileForPair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      if (await file.exists()) {
        await file.delete();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_remoteUrlPrefsKey(caregiverUserId, elderUserId));
      await prefs.remove(_androidUriPrefsKey(caregiverUserId, elderUserId));
      await prefs.remove(_androidUriPathPrefsKey(caregiverUserId, elderUserId));
      if (kDebugMode) {
        debugPrint(
          'voice storage: invalidated caregiver=$caregiverUserId elder=$elderUserId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('voice storage: invalidate failed: $e');
      }
    }
  }

  Future<String?> _cachedRemoteUrl({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_remoteUrlPrefsKey(caregiverUserId, elderUserId));
  }

  Future<void> _storeRemoteUrl({
    required int caregiverUserId,
    required int elderUserId,
    required String voiceUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _remoteUrlPrefsKey(caregiverUserId, elderUserId),
      voiceUrl.trim(),
    );
  }

  /// Downloads when missing or when [voiceUrl] changed (new R2 object / timestamp).
  Future<String?> ensureDownloaded({
    required int caregiverUserId,
    required int elderUserId,
    required String voiceUrl,
    bool forceRefresh = false,
  }) async {
    final trimmed = voiceUrl.trim();
    if (trimmed.isEmpty) return null;

    try {
      final target = await localFileForPair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      final cachedRemote = await _cachedRemoteUrl(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      final hasFile = await target.exists() && await target.length() > 0;
      if (!forceRefresh &&
          hasFile &&
          cachedRemote != null &&
          cachedRemote == trimmed) {
        return target.path;
      }

      if (hasFile) {
        await target.delete();
      }
      await invalidatePair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
          headers: const {'Accept': '*/*'},
        ),
      );
      final response = await dio.get<List<int>>(
        trimmed,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'voice storage: empty body caregiver=$caregiverUserId elder=$elderUserId',
          );
        }
        return null;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      await _storeRemoteUrl(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
        voiceUrl: trimmed,
      );
      if (Platform.isAndroid) {
        await _cacheAndroidNotificationContentUri(
          caregiverUserId: caregiverUserId,
          elderUserId: elderUserId,
          path: target.path,
        );
      }
      if (kDebugMode) {
        debugPrint(
          'voice storage: downloaded caregiver=$caregiverUserId elder=$elderUserId '
          'bytes=${bytes.length}',
        );
      }
      return target.path;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        final uri = e.requestOptions.uri;
        debugPrint(
          'voice storage: download failed caregiver=$caregiverUserId '
          'elder=$elderUserId status=${e.response?.statusCode} '
          'host=${uri.host}\n$st',
        );
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'voice storage: download failed caregiver=$caregiverUserId '
          'elder=$elderUserId: $e\n$st',
        );
      }
      return null;
    }
  }

  Future<String?> androidNotificationContentUri({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final file = await localFileForPair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      if (!await file.exists() || await file.length() == 0) return null;
      final path = file.path;
      final prefs = await SharedPreferences.getInstance();
      final cachedUri = prefs.getString(
        _androidUriPrefsKey(caregiverUserId, elderUserId),
      );
      final cachedPath = prefs.getString(
        _androidUriPathPrefsKey(caregiverUserId, elderUserId),
      );
      if (cachedUri != null &&
          cachedUri.isNotEmpty &&
          cachedPath == path) {
        return cachedUri;
      }
      return _cacheAndroidNotificationContentUri(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
        path: path,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'voice storage: android content uri failed '
          'caregiver=$caregiverUserId elder=$elderUserId: $e\n$st',
        );
      }
      return null;
    }
  }

  Future<String?> _cacheAndroidNotificationContentUri({
    required int caregiverUserId,
    required int elderUserId,
    required String path,
  }) async {
    final uri = await AndroidFamilyVoiceSoundUri.contentUriForFilePath(path);
    if (uri == null || uri.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _androidUriPrefsKey(caregiverUserId, elderUserId),
      uri,
    );
    await prefs.setString(
      _androidUriPathPrefsKey(caregiverUserId, elderUserId),
      path,
    );
    return uri;
  }

  Future<String?> notificationSoundReference({
    required int caregiverUserId,
    required int elderUserId,
  }) async {
    try {
      final file = await localFileForPair(
        caregiverUserId: caregiverUserId,
        elderUserId: elderUserId,
      );
      if (!await file.exists() || await file.length() == 0) return null;
      if (Platform.isIOS) {
        return localFileName(
          caregiverUserId: caregiverUserId,
          elderUserId: elderUserId,
        );
      }
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: sound ref failed: $e\n$st');
      }
      return null;
    }
  }
}
