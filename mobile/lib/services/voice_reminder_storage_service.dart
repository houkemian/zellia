import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists PRO family voice clips for custom local notification sounds.
///
/// **iOS:** Notification sounds must live under the app Library `Sounds/` folder.
/// DarwinNotificationDetails.sound is the *filename only* (e.g. `med_101_voice.m4a`),
/// not a full path — iOS resolves it from Library/Sounds at runtime.
///
/// **Android:** Custom sounds use a file URI via [UriAndroidNotificationSound].
/// We store under application documents (`getApplicationDocumentsDirectory()`)
/// because the channel sound URI must point at a readable file path on device storage.
class VoiceReminderStorageService {
  VoiceReminderStorageService._();

  static final VoiceReminderStorageService instance =
      VoiceReminderStorageService._();

  static String localFileNameForPlan(int planId) => 'med_${planId}_voice.m4a';

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

  Future<File> localFileForPlan(int planId) async {
    final dir = await notificationSoundsDirectory();
    return File('${dir.path}/${localFileNameForPlan(planId)}');
  }

  Future<bool> hasLocalVoiceForPlan(int planId) async {
    try {
      final file = await localFileForPlan(planId);
      return file.existsSync() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Returns absolute path on disk, or null if download failed.
  Future<String?> ensureDownloaded({
    required int planId,
    required String voiceUrl,
  }) async {
    final trimmed = voiceUrl.trim();
    if (trimmed.isEmpty) return null;

    try {
      final target = await localFileForPlan(planId);
      if (await target.exists() && await target.length() > 0) {
        return target.path;
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );
      final response = await dio.get<List<int>>(
        trimmed,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('voice storage: empty body planId=$planId');
        }
        return null;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: download failed planId=$planId: $e\n$st');
      }
      return null;
    }
  }

  /// iOS notification sound field: basename only. Android: full file path URI.
  Future<String?> notificationSoundReference(int planId) async {
    try {
      final file = await localFileForPlan(planId);
      if (!await file.exists() || await file.length() == 0) return null;
      if (Platform.isIOS) {
        return localFileNameForPlan(planId);
      }
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice storage: sound ref failed planId=$planId: $e\n$st');
      }
      return null;
    }
  }
}
