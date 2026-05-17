import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resolves a readable [content://] URI for Android notification channel sounds.
class AndroidFamilyVoiceSoundUri {
  AndroidFamilyVoiceSoundUri._();

  static const MethodChannel _channel =
      MethodChannel('one.dothings.zellia/family_voice');

  /// Decodes m4a to WAV (Android notification channels do not play AAC/m4a reliably).
  static Future<String?> prepareWavForNotification(String m4aPath) async {
    if (!Platform.isAndroid) return null;
    try {
      final wavPath = await _channel.invokeMethod<String>('prepareNotificationWav', {
        'path': m4aPath.trim(),
      });
      if (kDebugMode && wavPath != null) {
        debugPrint('[Notification][sound] wav ready path=$wavPath');
      }
      return wavPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] wav convert failed: $e');
      }
      return null;
    }
  }

  static Future<String?> contentUriForFilePath(String absolutePath) async {
    if (!Platform.isAndroid) return null;
    final trimmed = absolutePath.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = await _channel.invokeMethod<String>('notificationSoundUri', {
        'path': trimmed,
      });
      if (uri == null || uri.isEmpty) return null;
      if (kDebugMode) {
        debugPrint(
          '[Notification][sound] content uri=$uri path=$trimmed',
        );
      }
      return uri;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[Notification][sound] content uri failed: ${e.code} ${e.message}',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] content uri failed: $e');
      }
      return null;
    }
  }
}
