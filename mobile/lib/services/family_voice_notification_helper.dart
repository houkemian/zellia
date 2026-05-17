import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'android_family_voice_sound_uri.dart';
import 'voice_reminder_storage_service.dart';

/// Shared Android channel + [NotificationDetails] for family voice playback.
class FamilyVoiceNotificationHelper {
  FamilyVoiceNotificationHelper._();

  /// One channel per caregiver↔elder pair (Android channel sounds are immutable).
  static String channelIdFor({
    required int caregiverUserId,
    required int elderUserId,
  }) =>
      'med_family_voice_c${caregiverUserId}_e$elderUserId';

  static Future<AndroidNotificationSound?> ensureAndroidVoiceChannel(
    FlutterLocalNotificationsPlugin notifications, {
    required int caregiverUserId,
    required int elderUserId,
    required String soundPath,
    String? contentUri,
  }) async {
    final channelId = channelIdFor(
      caregiverUserId: caregiverUserId,
      elderUserId: elderUserId,
    );
    if (!Platform.isAndroid) return null;
    final file = File(soundPath);
    if (!await file.exists() || await file.length() == 0) {
      if (kDebugMode) {
        debugPrint('[Notification][sound] voice file missing path=$soundPath');
      }
      return null;
    }
    final resolvedUri = contentUri ??
        await AndroidFamilyVoiceSoundUri.contentUriForFilePath(soundPath);
    if (resolvedUri == null) {
      if (kDebugMode) {
        debugPrint(
          '[Notification][sound] content uri unavailable path=$soundPath',
        );
      }
      return null;
    }
    if (kDebugMode) {
      debugPrint(
        '[Notification][sound] channel=$channelId uri=$resolvedUri '
        'bytes=${await file.length()}',
      );
    }
    final androidSound = UriAndroidNotificationSound(resolvedUri);
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.deleteNotificationChannel('med_family_voice');
    await android?.deleteNotificationChannel('med_family_voice_v2');
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        '亲情语音服药提醒',
        description: '家人录制的服药提醒铃声',
        importance: Importance.max,
        playSound: true,
        sound: androidSound,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    return androidSound;
  }

  /// Returns notification details and a log label: `family_voice` or `default`.
  static Future<({NotificationDetails details, String soundKind})> build({
    required FlutterLocalNotificationsPlugin notifications,
    required int caregiverUserId,
    required int elderUserId,
    required String defaultAndroidChannelId,
    required String defaultAndroidChannelName,
    String? defaultAndroidChannelDescription,
  }) async {
    final storage = VoiceReminderStorageService.instance;
    final soundRef = await storage.notificationSoundReference(
      caregiverUserId: caregiverUserId,
      elderUserId: elderUserId,
    );
    final androidContentUri = Platform.isAndroid
        ? await storage.androidNotificationContentUri(
            caregiverUserId: caregiverUserId,
            elderUserId: elderUserId,
          )
        : null;

    if (soundRef != null && soundRef.isNotEmpty) {
      if (Platform.isAndroid) {
        final channelId = channelIdFor(
          caregiverUserId: caregiverUserId,
          elderUserId: elderUserId,
        );
        final androidSound = await ensureAndroidVoiceChannel(
          notifications,
          caregiverUserId: caregiverUserId,
          elderUserId: elderUserId,
          soundPath: soundRef,
          contentUri: androidContentUri,
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
                category: AndroidNotificationCategory.reminder,
                playSound: true,
                sound: androidSound,
                enableVibration: true,
                audioAttributesUsage: AudioAttributesUsage.notification,
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
