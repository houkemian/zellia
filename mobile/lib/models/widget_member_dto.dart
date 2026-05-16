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
    required this.medicationPlans,
    required this.syncedAtIso,
  });

  final String userId;
  final String nickname;
  final String latestBp;
  final String latestBpRecordedAtIso;
  final String latestBs;
  final String latestBsRecordedAtIso;
  final bool isBpNormal;
  final bool medTakenToday;
  final List<WidgetMedicationPlanDto> medicationPlans;
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
    'medDisplay': medicationPlans.map((p) => p.name).join('、'),
    'medicationPlans': medicationPlans.map((p) => p.toJson()).toList(),
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

    final rawPlans = json['medicationPlans'] as List<dynamic>?;
    final plans = rawPlans == null
        ? const <WidgetMedicationPlanDto>[]
        : rawPlans
            .map(
              (e) => WidgetMedicationPlanDto.fromJson(e as Map<String, dynamic>),
            )
            .toList();

    return WidgetMemberDto(
      userId: (json['userId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      latestBp: (json['latestBp'] as String?) ?? '暂无',
      latestBpRecordedAtIso: bpIso,
      latestBs: (json['latestBs'] as String?) ?? '暂无',
      latestBsRecordedAtIso: bsIso,
      isBpNormal: (json['isBpNormal'] as bool?) ?? true,
      medTakenToday: (json['medTakenToday'] as bool?) ?? false,
      medicationPlans: plans,
      syncedAtIso: synced,
    );
  }
}

/// One active medication plan for today (aggregated across time slots).
class WidgetMedicationPlanDto {
  const WidgetMedicationPlanDto({
    required this.planId,
    required this.name,
    required this.takenSlots,
    required this.totalSlots,
  });

  final int planId;
  final String name;
  final int takenSlots;
  final int totalSlots;

  bool get isComplete => totalSlots > 0 && takenSlots >= totalSlots;
  bool get isPartial => takenSlots > 0 && takenSlots < totalSlots;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'planId': planId,
    'name': name,
    'takenSlots': takenSlots,
    'totalSlots': totalSlots,
    'isComplete': isComplete,
  };

  factory WidgetMedicationPlanDto.fromJson(Map<String, dynamic> json) {
    return WidgetMedicationPlanDto(
      planId: json['planId'] as int? ?? 0,
      name: (json['name'] as String?) ?? '',
      takenSlots: json['takenSlots'] as int? ?? 0,
      totalSlots: json['totalSlots'] as int? ?? 0,
    );
  }
}
