import 'package:flutter/widgets.dart';

const Map<String, String> builtinAvatarAssetMap = <String, String>{
  'avatar_1': 'assets/avatars/1.png',
  'avatar_2': 'assets/avatars/2.png',
  'avatar_3': 'assets/avatars/3.png',
  'avatar_4': 'assets/avatars/4.png',
  'avatar_5': 'assets/avatars/5.png',
  'avatar_6': 'assets/avatars/6.png',
  'avatar_7': 'assets/avatars/7.png',
  'avatar_8': 'assets/avatars/8.png',
  'avatar_9': 'assets/avatars/9.png',
  'avatar_10': 'assets/avatars/10.png',
  'avatar_11': 'assets/avatars/11.png',
  'avatar_12': 'assets/avatars/12.png',
  'avatar_13': 'assets/avatars/13.png',
  'avatar_14': 'assets/avatars/14.png',
  'avatar_15': 'assets/avatars/15.png',
  'avatar_16': 'assets/avatars/16.png',
  'avatar_17': 'assets/avatars/17.png',
  'avatar_18': 'assets/avatars/18.png',
  'avatar_19': 'assets/avatars/19.png',
  'avatar_20': 'assets/avatars/20.png',
  'avatar_21': 'assets/avatars/21.png',
};

String? avatarValueToAssetPath(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  if (builtinAvatarAssetMap.containsKey(value)) {
    return builtinAvatarAssetMap[value];
  }
  if (builtinAvatarAssetMap.containsValue(value)) return value;
  if (value.startsWith('assets/')) return value;
  return null;
}

String? avatarSelectionKeyFromValue(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  if (builtinAvatarAssetMap.containsKey(value)) return value;
  for (final entry in builtinAvatarAssetMap.entries) {
    if (entry.value == value) return entry.key;
  }
  return null;
}

ImageProvider<Object>? avatarImageProvider(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  final assetPath = avatarValueToAssetPath(value);
  if (assetPath != null) return AssetImage(assetPath);
  return NetworkImage(value);
}
