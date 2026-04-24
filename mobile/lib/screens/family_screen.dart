import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';

const Map<String, String> _builtinAvatarAssetMap = <String, String>{
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

String? _avatarValueToAssetPath(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  if (_builtinAvatarAssetMap.containsKey(value)) {
    return _builtinAvatarAssetMap[value];
  }
  if (_builtinAvatarAssetMap.containsValue(value)) return value;
  if (value.startsWith('assets/')) return value;
  return null;
}

String? _avatarSelectionKeyFromValue(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  if (_builtinAvatarAssetMap.containsKey(value)) return value;
  for (final entry in _builtinAvatarAssetMap.entries) {
    if (entry.value == value) return entry.key;
  }
  return null;
}

ImageProvider<Object>? _avatarImageProvider(String? avatarValue) {
  final value = (avatarValue ?? '').trim();
  if (value.isEmpty) return null;
  final assetPath = _avatarValueToAssetPath(value);
  if (assetPath != null) return AssetImage(assetPath);
  return NetworkImage(value);
}

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  static const String _avatarMapPrefsKey = 'family_avatar_map_v1';
  bool _loading = true;
  bool _submitting = false;
  bool _profileLoading = true;
  String? _error;
  String? _inviteCode;
  CurrentUserProfileDto? _currentUserProfile;
  List<FamilyLinkDto> _pendingRequests = [];
  List<ApprovedElderDto> _approvedElders = [];
  List<ApprovedCaregiverDto> _approvedCaregivers = [];
  Map<int, String> _avatarMap = <int, String>{};

  @override
  void initState() {
    super.initState();
    _loadAvatarMap();
    _refresh();
  }

  Future<void> _loadAvatarMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_avatarMapPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = <int, String>{};
      final data = Map<String, dynamic>.from(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      for (final entry in data.entries) {
        final userId = int.tryParse(entry.key);
        final avatar = (entry.value as String?)?.trim() ?? '';
        if (userId != null && avatar.isNotEmpty) {
          map[userId] = avatar;
        }
      }
      if (!mounted) return;
      setState(() => _avatarMap = map);
    } catch (_) {
      // Ignore corrupt cache.
    }
  }

  Future<void> _persistAvatarMap(Map<int, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, String>{
      for (final entry in map.entries) '${entry.key}': entry.value,
    };
    await prefs.setString(_avatarMapPrefsKey, jsonEncode(payload));
  }

  String? _resolvedAvatarValue({required int userId, String? apiAvatar}) {
    final apiValue = (apiAvatar ?? '').trim();
    if (apiValue.isNotEmpty) return apiValue;
    return _avatarMap[userId];
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getCurrentUserProfile(),
        widget.api.getMyInviteCode(),
        widget.api.getPendingFamilyRequests(),
        widget.api.getApprovedElders(),
        widget.api.getApprovedCaregivers(),
      ]);
      if (!mounted) return;
      final profile = results[0] as CurrentUserProfileDto;
      final approvedElders = results[3] as List<ApprovedElderDto>;
      final approvedCaregivers = results[4] as List<ApprovedCaregiverDto>;
      final mergedAvatarMap = <int, String>{..._avatarMap};
      final profileAvatar = (profile.avatarUrl ?? '').trim();
      if (profileAvatar.isNotEmpty) {
        mergedAvatarMap[profile.id] = profileAvatar;
      }
      for (final elder in approvedElders) {
        final avatar = (elder.elderAvatarUrl ?? '').trim();
        if (avatar.isNotEmpty) {
          mergedAvatarMap[elder.elderId] = avatar;
        }
      }
      for (final caregiver in approvedCaregivers) {
        final avatar = (caregiver.caregiverAvatarUrl ?? '').trim();
        if (avatar.isNotEmpty) {
          mergedAvatarMap[caregiver.caregiverId] = avatar;
        }
      }
      setState(() {
        _currentUserProfile = profile;
        _inviteCode = (results[1] as FamilyInviteCodeDto).inviteCode;
        _pendingRequests = results[2] as List<FamilyLinkDto>;
        _approvedElders = approvedElders;
        _approvedCaregivers = approvedCaregivers;
        _avatarMap = mergedAvatarMap;
        _profileLoading = false;
      });
      await _persistAvatarMap(mergedAvatarMap);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _profileLoading = false;
        });
      }
    }
  }

  String get _displayNickname {
    final profile = _currentUserProfile;
    if (profile == null) return _text('用户', 'User');
    final nickname = profile.nickname.trim();
    if (nickname.isNotEmpty) return nickname;
    final email = profile.email.trim();
    if (email.isNotEmpty) return email.split('@').first;
    return profile.username;
  }

  String get _displayEmail {
    final profile = _currentUserProfile;
    if (profile == null) return '-';
    final email = profile.email.trim();
    if (email.isNotEmpty) return email;
    return profile.username;
  }

  void _openProfileSettings() async {
    final profile = _currentUserProfile;
    if (profile == null) return;
    final updated = await Navigator.of(context).push<CurrentUserProfileDto>(
      MaterialPageRoute(
        builder: (_) => _ProfileSettingsScreen(api: widget.api, profile: profile),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _currentUserProfile = updated);
  }

  Future<void> _applyByCode({
    required String inviteCode,
    String? elderAlias,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final code = inviteCode.trim();
    if (code.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.api.applyFamilyLinkByCode(code, elderAlias: elderAlias);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.familyApplySubmitted)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.familySubmitFailed(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _text(String zh, String en) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    return locale.startsWith('zh') ? zh : en;
  }

  ({String inviteCode, String? elderAlias})? _buildApplyPayload({
    required String inviteCodeRaw,
    required String elderAliasRaw,
  }) {
    final inviteCode = inviteCodeRaw.trim();
    if (inviteCode.isEmpty) return null;
    final elderAlias = elderAliasRaw.trim();
    return (
      inviteCode: inviteCode,
      elderAlias: elderAlias.isEmpty ? null : elderAlias,
    );
  }

  Future<void> _openApplyDialog() async {
    final codeController = TextEditingController();
    final aliasController = TextEditingController();
    try {
      final payload =
          await showModalBottomSheet<({String inviteCode, String? elderAlias})>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) {
              return StatefulBuilder(
                builder: (sheetContext, setSheetState) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _text('添加守护家人', 'Add a family member'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _text(
                              '请让家人在"让家人守护我"中复制邀请码，然后粘贴到下方',
                              'Ask your family to copy their invite code and paste it below',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: codeController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                            decoration: InputDecoration(
                              labelText: _text('家人邀请码', 'Family Invite Code'),
                              hintText: 'XXXXXXXX',
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF5FBFA),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: aliasController,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              labelText: _text(
                                '给 TA 写个备注（选填）',
                                'Alias for this person (optional)',
                              ),
                              hintText: _text(
                                '如：老公、妈妈',
                                'e.g. Husband, Mom',
                              ),
                              prefixIcon: const Icon(Icons.label_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF5FBFA),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(sheetContext).pop(),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(_text('取消', 'Cancel')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: () {
                                          final result = _buildApplyPayload(
                                            inviteCodeRaw: codeController.text,
                                            elderAliasRaw: aliasController.text,
                                          );
                                          if (result == null) return;
                                          Navigator.of(sheetContext).pop(result);
                                        },
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    backgroundColor: const Color(0xFF0E6A55),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.person_add_outlined),
                                  label: Text(_text('提交申请', 'Submit')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
      if (payload == null || !mounted) return;
      await _applyByCode(
        inviteCode: payload.inviteCode,
        elderAlias: payload.elderAlias,
      );
    } finally {
      codeController.dispose();
      aliasController.dispose();
    }
  }

  Future<void> _confirmUnbind({
    required int linkId,
    required String counterpartName,
    required bool isElderAction,
  }) async {
    final titleText = isElderAction
        ? _text('解除绑定', 'Unbind')
        : _text('取消关注', 'Unfollow');
    final contentText = isElderAction
        ? _text(
            '确定不再让 $counterpartName 查看您的健康数据吗？',
            'Stop allowing $counterpartName to view your health data?',
          )
        : _text('确认取消关注 $counterpartName？', 'Stop following $counterpartName?');
    final cancelText = _text('取消', 'Cancel');
    final confirmText = _text('确认', 'Confirm');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(titleText),
          content: Text(contentText),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelText),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      await widget.api.unbindFamilyLink(linkId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text('操作成功', 'Done'))));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('操作失败: $e', 'Action failed: $e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openApproveDialog(FamilyLinkDto item) async {
    final aliasController = TextEditingController(
      text: item.caregiverAlias ?? '',
    );
    final titleText = _text('同意申请', 'Approve request');
    final helperText = _text(
      '您想怎么称呼这位守护者？（例如：大儿子）',
      'How would you like to call this guardian? (e.g. Elder Son)',
    );
    final aliasLabelText = _text('守护者称呼', 'Guardian alias');
    final cancelText = _text('取消', 'Cancel');
    final approveText = _text('同意', 'Approve');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(titleText),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(helperText),
                const SizedBox(height: 10),
                TextField(
                  controller: aliasController,
                  decoration: InputDecoration(labelText: aliasLabelText),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(cancelText),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(approveText),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      await _decideRequest(
        item.id,
        true,
        caregiverAlias: aliasController.text.trim().isEmpty
            ? null
            : aliasController.text.trim(),
      );
    } finally {
      aliasController.dispose();
    }
  }

  Future<void> _decideRequest(
    int linkId,
    bool approved, {
    String? caregiverAlias,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      await widget.api.decideFamilyRequest(
        linkId: linkId,
        approved: approved,
        caregiverAlias: caregiverAlias,
      );
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.familyDecisionFailed(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _guardianDisplayName(ApprovedCaregiverDto item) {
    final alias = (item.caregiverAlias ?? '').trim();
    if (alias.isNotEmpty) return alias;
    return item.caregiverUsername;
  }

  String _guardianInitial(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, 1).toUpperCase();
  }

  void _selectElderView(ApprovedElderDto elder) {
    final l10n = AppLocalizations.of(context)!;
    final elderDisplayName = (elder.elderAlias ?? '').trim().isNotEmpty
        ? elder.elderAlias!.trim()
        : elder.elderUsername;
    setState(() {
      currentViewUserId = elder.elderId;
      currentViewUserName = elderDisplayName;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.familySwitchedToElderData(elderDisplayName))),
    );
  }

  void _clearElderView() {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      currentViewUserId = null;
      currentViewUserName = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.familySwitchedBackToMine)));
  }

  Future<void> _toggleWeeklyDigest(ApprovedElderDto elder, bool enabled) async {
    setState(() => _submitting = true);
    try {
      final updated = await widget.api.setWeeklyReportSubscription(
        linkId: elder.linkId,
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() {
        _approvedElders = _approvedElders
            .map((item) => item.linkId == updated.linkId ? updated : item)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? _text('已开启每周健康邮件', 'Weekly digest enabled')
                : _text('已关闭每周健康邮件', 'Weekly digest disabled'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('设置失败: $e', 'Update failed: $e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _copyInviteCode() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _inviteCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.familyInviteCodeCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isViewingSelf = currentViewUserId == null;
    final viewingName = (currentViewUserName ?? _text('家人', 'family member')).trim();
    final currentProfile = _currentUserProfile;
    final profileAvatarProvider = _avatarImageProvider(
      currentProfile == null
          ? null
          : _resolvedAvatarValue(
              userId: currentProfile.id,
              apiAvatar: currentProfile.avatarUrl,
            ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.familyTitle)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8F2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
                border: Border.all(color: const Color(0xFFCDEFE2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFFBFE9DB),
                        backgroundImage: profileAvatarProvider,
                        child: profileAvatarProvider != null
                            ? null
                            : Text(
                                _displayNickname.trim().isEmpty
                                    ? '?'
                                    : _displayNickname.trim().substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E6A55),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _profileLoading
                            ? const SizedBox(
                                height: 64,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayNickname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _displayEmail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      IconButton(
                        onPressed: _profileLoading ? null : _openProfileSettings,
                        tooltip: _text('修改资料', 'Edit profile'),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            children: isViewingSelf
                                ? [TextSpan(text: _text('当前正在查看我的数据', 'Currently viewing my data'))]
                                : [
                                    TextSpan(
                                      text: _text('当前正在查看 ', 'Currently viewing '),
                                    ),
                                    TextSpan(
                                      text: viewingName.isEmpty
                                          ? _text('家人', 'family member')
                                          : viewingName,
                                      style: const TextStyle(
                                        color: Color(0xFF0E6A55),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(text: _text(' 的数据', '\'s data')),
                                  ],
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: isViewingSelf
                            ? const SizedBox.shrink()
                            : TextButton.icon(
                                key: const ValueKey('switch-back-btn'),
                                onPressed: _clearElderView,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF0E6A55),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  minimumSize: const Size(0, 36),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: const BorderSide(
                                      color: Color(0xFF95D7C6),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                                label: Text(
                                  _text('切回我的', 'Switch back'),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_approvedElders.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.familyApprovedElders,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF555555),
                  ),
                ),
              ),
              ..._approvedElders.map((elder) {
                final isViewingThisElder = currentViewUserId == elder.elderId;
                final displayName = (elder.elderAlias ?? '').trim().isNotEmpty
                    ? elder.elderAlias!.trim()
                    : elder.elderUsername;
                final initial = displayName.isEmpty
                    ? '?'
                    : displayName.substring(0, 1).toUpperCase();
                final elderAvatarProvider = _avatarImageProvider(
                  _resolvedAvatarValue(
                    userId: elder.elderId,
                    apiAvatar: elder.elderAvatarUrl,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: isViewingThisElder
                        ? const Color(0xFFE6F7F1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: isViewingThisElder
                          ? null
                          : () => _selectElderView(elder),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isViewingThisElder
                                ? const Color(0xFF8DD4BF)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: isViewingThisElder
                                  ? const Color(0xFF0E6A55)
                                  : const Color(0xFFCCEEE5),
                              backgroundImage: elderAvatarProvider,
                              child: elderAvatarProvider == null
                                  ? Text(
                                      initial,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: isViewingThisElder
                                            ? Colors.white
                                            : const Color(0xFF0E6A55),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: isViewingThisElder
                                                ? const Color(0xFF0E6A55)
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      if (isViewingThisElder)
                                        Container(
                                          margin: const EdgeInsets.only(left: 6),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0E6A55),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            _text('查看中', 'Viewing'),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    elder.elderUsername,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Color(0xFF888888),
                              ),
                              onSelected: (value) {
                                if (value == 'unbind') {
                                  _confirmUnbind(
                                    linkId: elder.linkId,
                                    counterpartName:
                                        elder.elderAlias ?? elder.elderUsername,
                                    isElderAction: false,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  enabled: false,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _text('每周健康邮件', 'Weekly digest'),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Switch(
                                        value: elder.receiveWeeklyReport,
                                        onChanged: _submitting
                                            ? null
                                            : (v) {
                                                Navigator.of(context).pop();
                                                _toggleWeeklyDigest(elder, v);
                                              },
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem<String>(
                                  value: 'unbind',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_remove_outlined,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _text('取消关注', 'Unfollow'),
                                        style: TextStyle(
                                          color:
                                              Theme.of(context).colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.familyRoleElder,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _text(
                        '家人扫码后，将看到您的身份为：$_displayNickname',
                        'After your family scans, your identity will be shown as: $_displayNickname',
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.familyMyInviteCode(_inviteCode ?? "-"),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        IconButton(
                          onPressed:
                              (_inviteCode == null || _inviteCode!.isEmpty)
                              ? null
                              : _copyInviteCode,
                          tooltip: l10n.familyCopyInviteCode,
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    if (_pendingRequests.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      l10n.familyPendingRequests,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                      ..._pendingRequests.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.familyCaregiverAccount(
                                    item.caregiverUsername,
                                  ),
                                  style: const TextStyle(fontSize: 17),
                                ),
                              ),
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _decideRequest(item.id, false),
                                child: Text(l10n.familyReject),
                              ),
                              FilledButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _openApproveDialog(item),
                                child: Text(l10n.familyApprove),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_approvedCaregivers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _text('我的守护者 (已授权)', 'My Caregivers (Approved)'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                      ..._approvedCaregivers.map((item) {
                        final displayName = _guardianDisplayName(item);
                        final initial = _guardianInitial(displayName);
                        final caregiverAvatarProvider = _avatarImageProvider(
                          _resolvedAvatarValue(
                            userId: item.caregiverId,
                            apiAvatar: item.caregiverAvatarUrl,
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFDDDDDD),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: const Color(0xFFD9EFF8),
                                    backgroundImage: caregiverAvatarProvider,
                                    child: caregiverAvatarProvider == null
                                        ? Text(
                                            initial,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF176A8F),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.caregiverUsername,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Color(0xFF888888),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'unbind') {
                                        _confirmUnbind(
                                          linkId: item.linkId,
                                          counterpartName: displayName,
                                          isElderAction: true,
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'unbind',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.link_off_rounded,
                                              size: 18,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _text('解除绑定', 'Unbind'),
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.familyRoleCaregiver,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 4),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _openApplyDialog,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: const Color(0xFF0E6A55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.person_add_outlined),
                      label: Text(_text('添加守护家人', 'Add family member')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSettingsScreen extends StatefulWidget {
  const _ProfileSettingsScreen({required this.api, required this.profile});

  final ApiService api;
  final CurrentUserProfileDto profile;

  @override
  State<_ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<_ProfileSettingsScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _emailController;
  String? _selectedAvatarKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _emailController = TextEditingController(text: widget.profile.email);
    _selectedAvatarKey = _avatarSelectionKeyFromValue(widget.profile.avatarUrl);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _text(String zh, String en) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    return locale.startsWith('zh') ? zh : en;
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    final email = widget.profile.email.trim();
    if (nickname.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('昵称和账号邮箱不能为空', 'Nickname and email are required'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.api.updateCurrentUserProfile(
        nickname: nickname,
        email: email,
        avatarUrl: _selectedAvatarKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('保存失败: $e', 'Save failed: $e'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_text('个人资料设置', 'Profile settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nicknameController,
            decoration: InputDecoration(labelText: _text('昵称', 'Nickname')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            readOnly: true,
            enabled: false,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: _text('账号邮箱', 'Account email')),
          ),
          const SizedBox(height: 16),
          Text(
            _text('选择头像', 'Choose avatar'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _builtinAvatarAssetMap.entries.map((entry) {
              final avatarKey = entry.key;
              final assetPath = entry.value;
              final selected = _selectedAvatarKey == avatarKey;
              return InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: _saving
                    ? null
                    : () => setState(() => _selectedAvatarKey = avatarKey),
                child: Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF0E6A55)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(backgroundImage: AssetImage(assetPath)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(() => _selectedAvatarKey = null),
              icon: const Icon(Icons.person_off_outlined),
              label: Text(_text('不使用头像', 'Use no avatar')),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: Text(_saving ? _text('保存中...', 'Saving...') : _text('保存资料', 'Save profile')),
          ),
        ],
      ),
    );
  }
}
