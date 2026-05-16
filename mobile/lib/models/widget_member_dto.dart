/// Payload pushed to the OS widget store (App Group / Android widget prefs).
class WidgetMemberDto {
  const WidgetMemberDto({
    required this.userId,
    required this.nickname,
    required this.latestBp,
    required this.latestBpRecordedAtIso,
    required this.latestBs,
    required this.latestBsRecordedAtIso,
    required this.isBpNormal,
    required this.medTakenToday,
    required this.medDisplay,
    required this.syncedAtIso,
  });

  /// Target member numeric id as string (matches `member_data_<id>`; legacy `widget_data_<id>`).
  final String userId;
  final String nickname;
  final String latestBp;
  /// ISO-8601 UTC; Android/iOS format for display in system locale.
  final String latestBpRecordedAtIso;
  final String latestBs;
  final String latestBsRecordedAtIso;
  final bool isBpNormal;
  final bool medTakenToday;
  final String medDisplay;
  final String syncedAtIso;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'nickname': nickname,
    'latestBp': latestBp,
    'latestBpRecordedAt': latestBpRecordedAtIso,
    'latestBpRecordedAtIso': latestBpRecordedAtIso,
    'latestBs': latestBs,
    'latestBsRecordedAt': latestBsRecordedAtIso,
    'latestBsRecordedAtIso': latestBsRecordedAtIso,
    'isBpNormal': isBpNormal,
    'medTakenToday': medTakenToday,
    'medDisplay': medDisplay,
    'syncedAt': syncedAtIso,
    'syncedAtIso': syncedAtIso,
    'updatedAt': syncedAtIso,
  };

  factory WidgetMemberDto.fromJson(Map<String, dynamic> json) {
    final bpIso =
        (json['latestBpRecordedAtIso'] as String?)?.trim() ??
        (json['latestBpRecordedAt'] as String?)?.trim() ??
        '';
    final bsIso =
        (json['latestBsRecordedAtIso'] as String?)?.trim() ??
        (json['latestBsRecordedAt'] as String?)?.trim() ??
        '';
    final synced =
        (json['syncedAtIso'] as String?)?.trim() ??
        (json['syncedAt'] as String?)?.trim() ??
        (json['updatedAt'] as String?)?.trim() ??
        '';
    return WidgetMemberDto(
      userId: (json['userId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      latestBp: (json['latestBp'] as String?) ?? '暂无',
      latestBpRecordedAtIso: bpIso,
      latestBs: (json['latestBs'] as String?) ?? '暂无',
      latestBsRecordedAtIso: bsIso,
      isBpNormal: (json['isBpNormal'] as bool?) ?? true,
      medTakenToday: (json['medTakenToday'] as bool?) ?? false,
      medDisplay: (json['medDisplay'] as String?) ?? '',
      syncedAtIso: synced,
    );
  }
}
