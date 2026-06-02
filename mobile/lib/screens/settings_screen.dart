import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/user_avatar.dart';
import 'legal_document_screen.dart';

const _kPrimary = Color(0xFF0E6A55);
const _kTextMuted = Color(0xFF5E8274);
const _kNoAvatarDialogValue = '__none__';

/// App settings: profile, sign out, and legal / account actions.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    this.onLogout,
    this.initialProfile,
    this.onProfileUpdated,
  });

  final ApiService api;
  final Future<void> Function()? onLogout;
  final CurrentUserProfileDto? initialProfile;
  final ValueChanged<CurrentUserProfileDto>? onProfileUpdated;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CurrentUserProfileDto? _profile;
  bool _loadingProfile = false;
  bool _deleting = false;
  bool _savingProfile = false;

  late final TextEditingController _nicknameController;
  String? _selectedAvatarKey;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _nicknameController = TextEditingController(
      text: widget.initialProfile?.nickname ?? '',
    );
    _selectedAvatarKey = avatarSelectionKeyFromValue(
      widget.initialProfile?.avatarUrl,
    );
    if (_profile == null) {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  String _text(String zh, String en) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final profile = await widget.api.getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nicknameController.text = profile.nickname;
        _selectedAvatarKey = avatarSelectionKeyFromValue(profile.avatarUrl);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('加载资料失败: $e', 'Failed to load profile: $e')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final profile = _profile;
    if (profile == null) return;

    final nickname = _nicknameController.text.trim();
    final email = profile.email.trim();
    if (nickname.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('昵称和账号邮箱不能为空', 'Nickname and email are required'),
          ),
        ),
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      final updated = await widget.api.updateCurrentUserProfile(
        nickname: nickname,
        email: email,
        avatarUrl: _selectedAvatarKey,
      );
      if (!mounted) return;
      setState(() => _profile = updated);
      widget.onProfileUpdated?.call(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text('资料已保存', 'Profile saved'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('保存失败: $e', 'Save failed: $e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _openAvatarPicker() async {
    if (_savingProfile || _deleting) return;

    var pendingAvatarKey = _selectedAvatarKey;
    final avatarEntries = builtinAvatarAssetMap.entries.toList();
    final selected = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text('选择头像', 'Choose avatar')),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: avatarEntries.map((entry) {
                          final selected = pendingAvatarKey == entry.key;
                          return Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(32),
                              onTap: () {
                                setDialogState(
                                  () => pendingAvatarKey = entry.key,
                                );
                              },
                              child: Container(
                                width: 58,
                                height: 58,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? _kPrimary
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: scaledAvatarCircle(
                                  radius: 26,
                                  backgroundColor: const Color(0xFFE6F2EE),
                                  imageProvider: AssetImage(entry.value),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: () {
                            setDialogState(() => pendingAvatarKey = null);
                          },
                          child: Container(
                            width: 58,
                            height: 58,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: pendingAvatarKey == null
                                    ? _kPrimary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: const CircleAvatar(
                              backgroundColor: Color(0xFFE6F2EE),
                              child: Icon(
                                Icons.person_off_outlined,
                                color: _kTextMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_text('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(pendingAvatarKey ?? _kNoAvatarDialogValue),
                  style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                  child: Text(_text('保存', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || selected == null) return;

    final nextAvatarKey = selected == _kNoAvatarDialogValue ? null : selected;
    if (nextAvatarKey == _selectedAvatarKey) return;

    setState(() => _selectedAvatarKey = nextAvatarKey);
    await _saveProfile();
  }

  Future<void> _logout() async {
    final logout = widget.onLogout;
    if (logout == null) return;
    try {
      await logout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('退出失败', 'Sign out failed: $e'))),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_text('注销账号', 'Delete account')),
          content: Text(
            _text(
              '此操作将永久删除您的账号及所有个人数据（含体征记录与语音提醒），且无法恢复。确定继续？',
              'This permanently deletes your account and all personal data '
                  '(including vitals and voice reminders). This cannot be undone. Continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_text('取消', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_text('继续', 'Continue')),
            ),
          ],
        );
      },
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_text('最后确认', 'Final confirmation')),
          content: Text(
            _text(
              '请再次确认：您的账号将被立即注销，所有数据将从服务器清除。',
              'Please confirm again: your account will be deleted immediately and all data removed from our servers.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_text('取消', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_text('确认注销', 'Delete my account')),
            ),
          ],
        );
      },
    );
    if (second != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.api.deleteCurrentUserAccount();
      if (!mounted) return;
      await widget.onLogout?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('注销失败: $e', 'Account deletion failed: $e')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Widget _buildProfileSection(CurrentUserProfileDto profile) {
    final avatarProvider = avatarImageProvider(_selectedAvatarKey);
    final initial = _nicknameController.text.trim().isEmpty
        ? '?'
        : _nicknameController.text.trim().substring(0, 1).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(48),
            onTap: _savingProfile || _deleting ? null : _openAvatarPicker,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                scaledAvatarCircle(
                  radius: 40,
                  backgroundColor: const Color(0xFFCCEEE5),
                  imageProvider: avatarProvider,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nicknameController,
          enabled: !_savingProfile && !_deleting,
          decoration: InputDecoration(labelText: _text('昵称', 'Nickname')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey<String>(profile.email),
          initialValue: profile.email,
          readOnly: true,
          enabled: false,
          decoration: InputDecoration(
            labelText: _text('账号邮箱', 'Account email'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _savingProfile || _deleting ? null : _saveProfile,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: _kPrimary,
          ),
          child: Text(
            _savingProfile
                ? _text('保存中…', 'Saving…')
                : _text('保存资料', 'Save profile'),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _text('法律信息', 'Legal'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
                  color: _kTextMuted,
                ),
                title: Text(_text('隐私政策', 'Privacy Policy')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _deleting
                    ? null
                    : () => LegalDocumentScreen.openPrivacy(
                        context,
                        _text('隐私政策', 'Privacy Policy'),
                      ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.article_outlined, color: _kTextMuted),
                title: Text(_text('服务条款', 'Terms of Service')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _deleting
                    ? null
                    : () => LegalDocumentScreen.openTerms(
                        context,
                        _text('服务条款', 'Terms of Service'),
                      ),
              ),
              const Divider(height: 1, indent: 56),
              ExpansionTile(
                leading: const Icon(
                  Icons.manage_accounts_outlined,
                  color: _kTextMuted,
                ),
                title: Text(_text('账号管理', 'Account management')),
                tilePadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  end: 16,
                ),
                childrenPadding: EdgeInsets.zero,
                children: [
                  ExcludeFocus(
                    child: ListTile(
                      contentPadding: const EdgeInsetsDirectional.only(
                        start: 72,
                        end: 16,
                      ),
                      title: Text(
                        _text('注销账号', 'Delete account'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      subtitle: Text(
                        _text(
                          '永久删除账号和个人数据',
                          'Permanently delete account and personal data',
                        ),
                      ),
                      onTap: _deleting ? null : _confirmDeleteAccount,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(title: Text(_text('设置', 'Settings'))),
      body: _loadingProfile && profile == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (profile != null) _buildProfileSection(profile),
                    if (widget.onLogout != null) ...[
                      OutlinedButton.icon(
                        onPressed: _deleting ? null : _logout,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: _kTextMuted,
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(_text('退出登录', 'Sign out')),
                      ),
                      const SizedBox(height: 40),
                    ],
                    _buildLegalSection(),
                  ],
                ),
                if (_deleting)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66FFFFFF),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
    );
  }
}
