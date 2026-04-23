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
  String? _error;
  String? _inviteCode;
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
        widget.api.getMyInviteCode(),
        widget.api.getPendingFamilyRequests(),
        widget.api.getApprovedElders(),
        widget.api.getApprovedCaregivers(),
      ]);
      if (!mounted) return;
      setState(() {
        _inviteCode = (results[0] as FamilyInviteCodeDto).inviteCode;
        _pendingRequests = results[1] as List<FamilyLinkDto>;
        _approvedElders = results[2] as List<ApprovedElderDto>;
        _approvedCaregivers = results[3] as List<ApprovedCaregiverDto>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.familyApplySubmitted)),
      );
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
    return (inviteCode: inviteCode, elderAlias: elderAlias.isEmpty ? null : elderAlias);
  }

  Future<void> _openApplyDialog() async {
    final codeController = TextEditingController();
    final aliasController = TextEditingController();
    final titleText = _text('申请绑定长辈', 'Request Elder Link');
    final codeLabelText = _text('长辈邀请码', 'Elder Invite Code');
    final aliasLabelText = _text('备注名 (如：妈妈、李奶奶)', 'Alias (e.g. Mom, Grandma Li)');
    final cancelText = _text('取消', 'Cancel');
    final submitText = _text('提交申请', 'Submit');
    try {
      final payload = await showDialog<({String inviteCode, String? elderAlias})>(
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
                  decoration: InputDecoration(
                    labelText: codeLabelText,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: aliasController,
                  decoration: InputDecoration(
                    labelText: aliasLabelText,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: _submitting ? null : () => Navigator.of(dialogContext).pop(),
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
    final titleText = isElderAction ? _text('解除绑定', 'Unbind') : _text('取消关注', 'Unfollow');
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
              style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('操作成功', 'Done'))),
      );
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
    final aliasController = TextEditingController(text: item.caregiverAlias ?? '');
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
                  decoration: InputDecoration(
                    labelText: aliasLabelText,
                  ),
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
        caregiverAlias: aliasController.text.trim().isEmpty ? null : aliasController.text.trim(),
      );
    } finally {
      aliasController.dispose();
    }
  }

  Future<void> _decideRequest(int linkId, bool approved, {String? caregiverAlias}) async {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.familySwitchedBackToMine)),
    );
  }

  Future<void> _copyInviteCode() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _inviteCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.familyInviteCodeCopied)),
    );
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
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.familyRoleElder, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.familyMyInviteCode(_inviteCode ?? "-"),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        IconButton(
                          onPressed: (_inviteCode == null || _inviteCode!.isEmpty) ? null : _copyInviteCode,
                          tooltip: l10n.familyCopyInviteCode,
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(l10n.familyPendingRequests, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                                  l10n.familyCaregiverAccount(item.caregiverUsername),
                                  style: const TextStyle(fontSize: 17),
                                ),
                              ),
                              TextButton(
                                onPressed: _submitting ? null : () => _decideRequest(item.id, false),
                                child: Text(l10n.familyReject),
                              ),
                              FilledButton(
                                onPressed: _submitting ? null : () => _openApproveDialog(item),
                                child: Text(l10n.familyApprove),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      _text('我的守护者 (已授权)', 'My Caregivers (Approved)'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (_approvedCaregivers.isEmpty)
                      Text(_text('暂无已授权守护者', 'No approved caregivers'))
                    else
                      ..._approvedCaregivers.map(
                        (item) {
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
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                child: Text(_text('解除绑定', 'Unbind')),
                              ),
                            ),
                          ),
                        );
                        },
                      ),
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
                    Text(l10n.familyRoleCaregiver, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _submitting ? null : _openApplyDialog,
                      child: Text(_text('申请绑定', 'Request link')),
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.familyApprovedElders, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_approvedElders.isEmpty)
                      Text(l10n.familyNoApprovedElders)
                    else
                      ..._approvedElders.map(
                        (elder) {
                          final isViewingThisElder = currentViewUserId == elder.elderId;
                          return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              selected: isViewingThisElder,
                              selectedTileColor: const Color(0xFFE6F7F1),
                              onTap: isViewingThisElder ? null : () => _selectElderView(elder),
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
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(elder.elderUsername),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'unbind') {
                                    _confirmUnbind(
                                      linkId: elder.linkId,
                                      counterpartName: elder.elderAlias ?? elder.elderUsername,
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
                        },
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: isViewingSelf ? null : _clearElderView,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: isViewingSelf ? const Color(0xFF0E6A55) : null,
                        side: BorderSide(
                          color: isViewingSelf ? const Color(0xFF95D7C6) : const Color(0xFFBDBDBD),
                        ),
                        backgroundColor: isViewingSelf ? const Color(0xFFE6F7F1) : null,
                      ),
                      child: Text(
                        isViewingSelf
                            ? _text('当前正在查看我的数据', 'Currently viewing my data')
                            : l10n.familySwitchBackToMine,
                      ),
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
