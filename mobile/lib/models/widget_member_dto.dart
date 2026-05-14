/// Payload pushed to the OS widget store (App Group / Android widget prefs).
class WidgetMemberDto {
  const WidgetMemberDto({
    required this.userId,
    required this.nickname,
    required this.latestBp,
    required this.isBpNormal,
    required this.medTakenToday,
    required this.updatedAt,
  });

  /// Target member numeric id as string (matches `member_data_<id>`; legacy `widget_data_<id>`).
  final String userId;
  final String nickname;
  final String latestBp;
  final bool isBpNormal;
  final bool medTakenToday;
  final String updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'nickname': nickname,
    'latestBp': latestBp,
    'isBpNormal': isBpNormal,
    'medTakenToday': medTakenToday,
    'updatedAt': updatedAt,
  };

  factory WidgetMemberDto.fromJson(Map<String, dynamic> json) {
    return WidgetMemberDto(
      userId: (json['userId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      latestBp: (json['latestBp'] as String?) ?? '暂无',
      isBpNormal: (json['isBpNormal'] as bool?) ?? true,
      medTakenToday: (json['medTakenToday'] as bool?) ?? false,
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }
}

// Markdown — native reads for this DTO shape:
// - **iOS**: `UserDefaults(suiteName: "group.one.dothings.zellia")` → key `member_data_<userId>` (JSON); index `cached_widget_members`.
// - **Android**: same keys in widget `SharedPreferences` / Glance **configuration** to pick `userId`, then decode JSON in `onUpdate`.
