import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists PRO family voice clips for custom local notification sounds.
///
/// One shared file per elder user — all medication reminders use the same sound.
///
/// **iOS:** Notification sounds must live under the app Library `Sounds/` folder.
/// DarwinNotificationDetails.sound is the *filename only* (e.g. `family_42_voice.m4a`),
/// not a full path — iOS resolves it from Library/Sounds at runtime.
///
/// **Android:** Custom sounds use a file URI via [UriAndroidNotificationSound].
/// We store under application documents (`getApplicationDocumentsDirectory()`)
/// because the channel sound URI must point at a readable file path on device storage.
class VoiceReminderStorageService {
  VoiceReminderStorageService._();

  static final VoiceReminderStorageService instance =
      VoiceReminderStorageService._();

  static String localFileNameForUser(int userId) => 'family_${userId}_voice.m4a';

  /// iOS: Library/Sounds — required for custom notification sounds.
  /// Android: app documents directory (see class doc).
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
      final docs = await getApplicationDocumentsDirectory();
      final voices = Directory('${docs.path}/medication_voices');
      if (!await voices.exists()) {
        await voices.create(recursive: true);
      }
      return voices;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: failed to resolve sounds dir: $e\n$st');
      }
      rethrow;
    }
  }

  Future<File> localFileForUser(int userId) async {
    final dir = await notificationSoundsDirectory();
    return File('${dir.path}/${localFileNameForUser(userId)}');
  }

  Future<bool> hasLocalVoiceForUser(int userId) async {
    try {
      final file = await localFileForUser(userId);
      return file.existsSync() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Returns absolute path on disk, or null if download failed.
  Future<String?> ensureDownloaded({
    required int userId,
    required String voiceUrl,
  }) async {
    final trimmed = voiceUrl.trim();
    if (trimmed.isEmpty) return null;

    try {
      final target = await localFileForUser(userId);
      if (await target.exists() && await target.length() > 0) {
        return target.path;
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
          headers: const {
            'Accept': '*/*',
          },
        ),
      );
      final response = await dio.get<List<int>>(
        trimmed,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('voice storage: empty body userId=$userId');
        }
        return null;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        final uri = e.requestOptions.uri;
        debugPrint(
          'voice storage: download failed userId=$userId '
          'status=${e.response?.statusCode} host=${uri.host} path=${uri.path}\n$st',
        );
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: download failed userId=$userId: $e\n$st');
      }
      return null;
    }
  }

  /// iOS notification sound field: basename only. Android: full file path URI.
  Future<String?> notificationSoundReference(int userId) async {
    try {
      final file = await localFileForUser(userId);
      if (!await file.exists() || await file.length() == 0) return null;
      if (Platform.isIOS) {
        return localFileNameForUser(userId);
      }
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: sound ref failed userId=$userId: $e\n$st');
      }
      return null;
    }
  }
}
