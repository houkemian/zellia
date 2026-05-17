import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android family voice: FileProvider URIs and native poke playback.
class ZelliaFamilyVoice {
  ZelliaFamilyVoice._();

  static const MethodChannel _channel =
      MethodChannel('one.dothings.zellia/family_voice');

  static Future<String?> notificationSoundUri(String absolutePath) async {
    if (!Platform.isAndroid) return null;
    final trimmed = absolutePath.trim();
    if (trimmed.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('notificationSoundUri', {
        'path': trimmed,
      });
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] plugin missing: $e');
      }
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[Notification][sound] uri failed: ${e.code} ${e.message}',
        );
      }
      return null;
    }
  }

  /// Plays m4a via [MediaPlayer] (works from FCM background / screen off).
  static Future<bool> playPoke(String absolutePath) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('playPoke', {
        'path': absolutePath.trim(),
      });
      return ok == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] native playPoke failed: $e');
      }
      return false;
    }
  }

  static Future<void> stopPoke() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopPoke');
    } catch (_) {}
  }
}
