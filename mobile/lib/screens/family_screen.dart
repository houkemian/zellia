import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.api.applyFamilyLinkByCode(code);
      if (!mounted) return;
      _inviteCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('申请已提交，等待长辈审核')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _decideRequest(int linkId, bool approved) async {
    setState(() => _submitting = true);
    try {
      await widget.api.decideFamilyRequest(linkId: linkId, approved: approved);
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('处理失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _selectElderView(ApprovedElderDto elder) {
    setState(() {
      currentViewUserId = elder.elderId;
      currentViewUserName = elder.elderUsername;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换为查看 ${elder.elderUsername} 的健康数据')),
    );
  }

  void _clearElderView() {
    setState(() {
      currentViewUserId = null;
      currentViewUserName = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已切换回查看自己的数据')),
    );
  }

  Future<void> _copyInviteCode() async {
    final code = _inviteCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀请码已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('亲情账号关联')),
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
                    const Text('我是长辈', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text('我的邀请码: ${_inviteCode ?? "-"}', style: const TextStyle(fontSize: 18)),
                        ),
                        IconButton(
                          onPressed: (_inviteCode == null || _inviteCode!.isEmpty) ? null : _copyInviteCode,
                          tooltip: '复制邀请码',
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('待审核申请', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_pendingRequests.isEmpty)
                      const Text('暂无待审核申请')
                    else
                      ..._pendingRequests.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '子女账号: ${item.caregiverUsername}',
                                  style: const TextStyle(fontSize: 17),
                                ),
                              ),
                              TextButton(
                                onPressed: _submitting ? null : () => _decideRequest(item.id, false),
                                child: const Text('拒绝'),
                              ),
                              FilledButton(
                                onPressed: _submitting ? null : () => _decideRequest(item.id, true),
                                child: const Text('同意'),
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
                    const Text('我是子女', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: '输入长辈邀请码'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _submitting ? null : _applyByCode,
                      child: const Text('申请绑定'),
                    ),
                    const SizedBox(height: 16),
                    const Text('已关联长辈', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_approvedElders.isEmpty)
                      const Text('暂无已关联长辈')
                    else
                      ..._approvedElders.map(
                        (elder) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: () => _selectElderView(elder),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            child: Text('查看 ${elder.elderUsername} 的数据'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _clearElderView,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: const Text('切回查看我的数据'),
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
