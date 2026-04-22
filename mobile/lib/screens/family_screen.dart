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
  final TextEditingController _inviteCodeController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _inviteCode;
  List<FamilyLinkDto> _pendingRequests = [];
  List<ApprovedElderDto> _approvedElders = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
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
      ]);
      if (!mounted) return;
      setState(() {
        _inviteCode = (results[0] as FamilyInviteCodeDto).inviteCode;
        _pendingRequests = results[1] as List<FamilyLinkDto>;
        _approvedElders = results[2] as List<ApprovedElderDto>;
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

  Future<void> _applyByCode() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.api.applyFamilyLinkByCode(code);
      if (!mounted) return;
      _inviteCodeController.clear();
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

  Future<void> _decideRequest(int linkId, bool approved) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      await widget.api.decideFamilyRequest(linkId: linkId, approved: approved);
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

  void _selectElderView(ApprovedElderDto elder) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      currentViewUserId = elder.elderId;
      currentViewUserName = elder.elderUsername;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.familySwitchedToElderData(elder.elderUsername))),
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
                                onPressed: _submitting ? null : () => _decideRequest(item.id, true),
                                child: Text(l10n.familyApprove),
                              ),
                            ],
                          ),
                        ),
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
                    TextField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: l10n.familyInviteCodeInputLabel),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _submitting ? null : _applyByCode,
                      child: Text(l10n.familyApplyLink),
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.familyApprovedElders, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_approvedElders.isEmpty)
                      Text(l10n.familyNoApprovedElders)
                    else
                      ..._approvedElders.map(
                        (elder) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: () => _selectElderView(elder),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            child: Text(l10n.familyViewElderData(elder.elderUsername)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _clearElderView,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
