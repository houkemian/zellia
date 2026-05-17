import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'voice_reminder_storage_service.dart';

/// Shared Android channel + [NotificationDetails] for family voice m4a playback.
class FamilyVoiceNotificationHelper {
  FamilyVoiceNotificationHelper._();

  static const String channelId = 'med_family_voice';

  static Future<AndroidNotificationSound?> ensureAndroidVoiceChannel(
    FlutterLocalNotificationsPlugin notifications,
    String soundPath,
  ) async {
    if (!Platform.isAndroid) return null;
    final file = File(soundPath);
    if (!await file.exists() || await file.length() == 0) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] voice file missing path=$soundPath');
      }
      return null;
    }
    final uri = Uri.file(soundPath).toString();
    if (kDebugMode) {
      debugPrint(
        '[Notification][sound] channel=$channelId uri=$uri bytes=${await file.length()}',
      );
    }
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        '亲情语音服药提醒',
        description: '家人录制的服药提醒铃声',
        importance: Importance.max,
        playSound: true,
        sound: UriAndroidNotificationSound(uri),
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    return UriAndroidNotificationSound(uri);
  }

  /// Returns notification details and a log label: `family_voice` or `default`.
  static Future<({NotificationDetails details, String soundKind})> build({
    required FlutterLocalNotificationsPlugin notifications,
    required int elderUserId,
    required String defaultAndroidChannelId,
    required String defaultAndroidChannelName,
    String? defaultAndroidChannelDescription,
  }) async {
    final soundRef =
        await VoiceReminderStorageService.instance.notificationSoundReference(
      elderUserId,
    );

    if (soundRef != null && soundRef.isNotEmpty) {
      if (Platform.isAndroid) {
        final androidSound = await ensureAndroidVoiceChannel(
          notifications,
          soundRef,
        );
        if (androidSound != null) {
          return (
            details: NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                '亲情语音服药提醒',
                channelDescription: '家人录制的服药提醒铃声',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                sound: androidSound,
              ),
            ),
            soundKind: 'family_voice_uri',
          );
        }
      } else if (Platform.isIOS) {
        return (
          details: NotificationDetails(
            iOS: DarwinNotificationDetails(
              sound: soundRef,
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          soundKind: 'ios_family_voice',
        );
      }
    }

    return (
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          defaultAndroidChannelId,
          defaultAndroidChannelName,
          channelDescription: defaultAndroidChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      soundKind: 'default',
    );
  }
}
