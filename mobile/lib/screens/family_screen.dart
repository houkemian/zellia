import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  bool _loading = true;
  bool _submitting = false;
  bool _profileLoading = true;
  String? _error;
  String? _inviteCode;
  CurrentUserProfileDto? _currentUserProfile;
  List<FamilyLinkDto> _pendingRequests = [];
  List<ApprovedElderDto> _approvedElders = [];
  List<ApprovedCaregiverDto> _approvedCaregivers = [];

  @override
  void initState() {
    super.initState();
    _refresh();
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
      setState(() {
        _currentUserProfile = results[0] as CurrentUserProfileDto;
        _inviteCode = (results[1] as FamilyInviteCodeDto).inviteCode;
        _pendingRequests = results[2] as List<FamilyLinkDto>;
        _approvedElders = results[3] as List<ApprovedElderDto>;
        _approvedCaregivers = results[4] as List<ApprovedCaregiverDto>;
        _profileLoading = false;
      });
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
    final titleText = _text('申请绑定长辈', 'Request Elder Link');
    final codeLabelText = _text('家人邀请码', 'Family Invite Code');
    final aliasLabelText = _text(
      '给家人写个备注 (如：老公、妈妈)',
      'Add a note for family (e.g. Husband, Mom)',
    );
    final cancelText = _text('取消', 'Cancel');
    final submitText = _text('提交申请', 'Submit');
    try {
      final payload =
          await showDialog<({String inviteCode, String? elderAlias})>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(titleText),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: codeLabelText),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: aliasController,
                      decoration: InputDecoration(labelText: aliasLabelText),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: Text(cancelText),
                  ),
                  FilledButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            final result = _buildApplyPayload(
                              inviteCodeRaw: codeController.text,
                              elderAliasRaw: aliasController.text,
                            );
                            if (result == null) return;
                            Navigator.of(dialogContext).pop(result);
                          },
                    child: Text(submitText),
                  ),
                ],
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
                        backgroundImage:
                            (_currentUserProfile?.avatarUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(_currentUserProfile!.avatarUrl!.trim())
                            : null,
                        child:
                            (_currentUserProfile?.avatarUrl ?? '').trim().isNotEmpty
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
                  Text(
                    isViewingSelf
                        ? _text('当前正在查看我的数据', 'Currently viewing my data')
                        : _text(
                            '当前正在查看${currentViewUserName ?? _text('家人', 'family member')}的数据',
                            'Currently viewing ${(currentViewUserName ?? 'family member')}\'s data',
                          ),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
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
                    const SizedBox(height: 14),
                    Text(
                      l10n.familyPendingRequests,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_pendingRequests.isEmpty)
                      Text(l10n.familyNoPendingRequests)
                    else
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
                    const SizedBox(height: 14),
                    Text(
                      _text('我的守护者 (已授权)', 'My Caregivers (Approved)'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_approvedCaregivers.isEmpty)
                      Text(_text('暂无已授权守护者', 'No approved caregivers'))
                    else
                      ..._approvedCaregivers.map((item) {
                        final displayName = _guardianDisplayName(item);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFDCEFF8),
                                child: Text(
                                  _guardianInitial(displayName),
                                  style: const TextStyle(
                                    color: Color(0xFF176A55),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                item.caregiverUsername,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              trailing: TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _confirmUnbind(
                                        linkId: item.linkId,
                                        counterpartName: displayName,
                                        isElderAction: true,
                                      ),
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                                child: Text(_text('解除绑定', 'Unbind')),
                              ),
                            ),
                          ),
                        );
                      }),
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
                    FilledButton(
                      onPressed: _submitting ? null : _openApplyDialog,
                      child: Text(_text('申请绑定', 'Request link')),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.familyApprovedElders,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_approvedElders.isEmpty)
                      Text(l10n.familyNoApprovedElders)
                    else
                      ..._approvedElders.map((elder) {
                        final isViewingThisElder =
                            currentViewUserId == elder.elderId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              selected: isViewingThisElder,
                              selectedTileColor: const Color(0xFFE6F7F1),
                              isThreeLine: true,
                              onTap: isViewingThisElder
                                  ? null
                                  : () => _selectElderView(elder),
                              title: Text(
                                isViewingThisElder
                                    ? _text(
                                        '当前查看：${elder.elderAlias ?? elder.elderUsername}',
                                        'Currently viewing: ${elder.elderAlias ?? elder.elderUsername}',
                                      )
                                    : _text(
                                        '查看 ${elder.elderAlias ?? elder.elderUsername} 的数据',
                                        'View ${(elder.elderAlias ?? elder.elderUsername)} data',
                                      ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(elder.elderUsername),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _text('周报', 'Digest'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Switch(
                                        value: elder.receiveWeeklyReport,
                                        onChanged: _submitting
                                            ? null
                                            : (v) =>
                                                  _toggleWeeklyDigest(elder, v),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'unbind') {
                                    _confirmUnbind(
                                      linkId: elder.linkId,
                                      counterpartName:
                                          elder.elderAlias ??
                                          elder.elderUsername,
                                      isElderAction: false,
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem<String>(
                                    value: 'unbind',
                                    child: Text(_text('取消关注', 'Unfollow')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: isViewingSelf ? null : _clearElderView,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: isViewingSelf
                            ? const Color(0xFF0E6A55)
                            : null,
                        side: BorderSide(
                          color: isViewingSelf
                              ? const Color(0xFF95D7C6)
                              : const Color(0xFFBDBDBD),
                        ),
                        backgroundColor: isViewingSelf
                            ? const Color(0xFFE6F7F1)
                            : null,
                      ),
                      child: Text(l10n.familySwitchBackToMine),
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
  late final TextEditingController _avatarController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _emailController = TextEditingController(text: widget.profile.email);
    _avatarController = TextEditingController(text: widget.profile.avatarUrl ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  String _text(String zh, String en) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    return locale.startsWith('zh') ? zh : en;
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final avatarUrl = _avatarController.text.trim();
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
        avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
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
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: _text('账号邮箱', 'Account email')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _avatarController,
            decoration: InputDecoration(labelText: _text('头像链接（可选）', 'Avatar URL (optional)')),
          ),
          const SizedBox(height: 16),
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
