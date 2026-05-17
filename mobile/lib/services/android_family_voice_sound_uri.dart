import 'package:zellia_family_voice/zellia_family_voice.dart';

/// Android family voice platform URIs (registered Flutter plugin).
class AndroidFamilyVoiceSoundUri {
  AndroidFamilyVoiceSoundUri._();

  static Future<String?> contentUriForFilePath(String absolutePath) =>
      ZelliaFamilyVoice.notificationSoundUri(absolutePath);

  static Future<bool> playPoke(String absolutePath) =>
      ZelliaFamilyVoice.playPoke(absolutePath);
}
