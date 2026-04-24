import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';

/// OAuth2 password flow: POST /auth/login with form fields.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onLoggedIn,
  });

  final ApiService api;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    final l10n = AppLocalizations.of(context)!;
    const loginPath = '/auth/login';
    final username = _userController.text.trim();
    final password = _passController.text;
    if (kDebugMode) {
      debugPrint('[LOGIN] Tap login button');
      debugPrint('[LOGIN] Username="$username"');
      debugPrint('[LOGIN] Request URL=${widget.api.debugUrl(loginPath)}');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.api.postForm(loginPath, {
        'username': username,
        'password': password,
        'grant_type': 'password',
      });
      if (res.statusCode != 200) {
        final msg =
            '${l10n.loginFailed(res.statusCode)}\nURL: ${widget.api.debugUrl(loginPath)}\nStatus: ${res.statusCode}';
        setState(() => _error = msg);
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      if (token == null || token.isEmpty) {
        setState(() => _error = l10n.invalidResponse);
        return;
      }
      await widget.api.saveToken(token);
      if (kDebugMode) debugPrint('[LOGIN] Success, token saved');
      widget.onLoggedIn();
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN] Exception: $e');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitRegister() async {
    final account = _userController.text.trim();
    final password = _passController.text;

    if (account.isEmpty) {
      setState(() => _error = _text('请输入账号或邮箱', 'Please enter account or email.'));
      return;
    }
    if (password.length < 6) {
      setState(() => _error = _text('密码至少 6 位', 'Password must be at least 6 characters.'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registerRes = await widget.api.post('/auth/register', body: {
        'username': account,
        'password': password,
      });
      if (registerRes.statusCode != 201) {
        setState(
          () => _error = _text(
            '注册失败 (${registerRes.statusCode})',
            'Sign up failed (${registerRes.statusCode}).',
          ),
        );
        return;
      }
      await _submitLogin();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _text(String zh, String en) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }

  void _switchMode(bool registerMode) {
    setState(() {
      _registerMode = registerMode;
      _error = null;
      _passController.clear();
    });
  }

  Future<void> _openActivationWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ActivationWizardScreen(
          api: widget.api,
          onActivated: widget.onLoggedIn,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4FFFB), Color(0xFFE8F8F2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 1.5,
                  color: Colors.white.withValues(alpha: 0.96),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/images/logo_with_name.png',
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _registerMode ? _text('账号注册', 'Sign Up') : l10n.loginTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _registerMode
                              ? _text('请输入账号（可用邮箱）和密码完成注册', 'Create your account with username/email and password')
                              : _text('欢迎回来，请登录继续使用', 'Welcome back, sign in to continue'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6B64)),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _userController,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            labelText: _registerMode ? _text('账号/邮箱', 'Account/Email') : _text('账号/邮箱', 'Account/Email'),
                          ),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passController,
                          decoration: InputDecoration(labelText: l10n.passwordLabel),
                          obscureText: true,
                          onSubmitted: (_) => _registerMode ? _submitRegister() : _submitLogin(),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _busy ? null : () => _switchMode(!_registerMode),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _registerMode
                                  ? _text('已有账号？返回登录', 'Already have an account? Sign in')
                                  : _text('没有账号？Sign up', "Don't have an account? Sign up"),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF1A7F68),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 18)),
                        ],
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _busy ? null : (_registerMode ? _submitRegister : _submitLogin),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          child: _busy
                              ? const CircularProgressIndicator()
                              : Text(_registerMode ? _text('注册并登录', 'Sign Up & Sign In') : l10n.loginButton),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _openActivationWizard,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            side: const BorderSide(color: Color(0xFF0E6A55), width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.vpn_key_rounded),
                          label: Text(
                            _text('我有亲情激活码', 'I have a family activation code'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0E6A55),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivationWizardScreen extends StatefulWidget {
  const _ActivationWizardScreen({
    required this.api,
    required this.onActivated,
  });

  final ApiService api;
  final VoidCallback onActivated;

  @override
  State<_ActivationWizardScreen> createState() => _ActivationWizardScreenState();
}

class _ActivationWizardScreenState extends State<_ActivationWizardScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  int _step = 0;
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _text(String zh, String en) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }

  Future<void> _validateCodeStep() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = _text('请输入 6 位激活码', 'Please enter a 6-character code.'));
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _completeActivation() async {
    final code = _codeController.text.trim().toUpperCase();
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _error = _text('密码至少 6 位', 'Password must be at least 6 characters.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.activateElderAccount(
        activationCode: code,
        newPassword: password,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_text('激活成功', 'Activation success')),
          content: Text(
            _text(
              '您的登录账号是 ${result.username}，请记下它或让子女帮您保存。',
              'Your login account is ${result.username}. Please save it.',
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text('我记住了', 'Got it')),
            ),
          ],
        ),
      );
      await widget.api.saveToken(result.accessToken);
      if (!mounted) return;
      widget.onActivated();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _text('激活失败: $e', 'Activation failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToFinalStep() {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _error = _text('密码至少 6 位', 'Password must be at least 6 characters.'));
      return;
    }
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_text('亲情激活', 'Family activation'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _text('激活长辈账号', 'Activate elder account'),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _text('按步骤完成设置后即可直接登录', 'Complete the steps to sign in directly'),
            style: const TextStyle(fontSize: 21, color: Color(0xFF4F6B64)),
          ),
          const SizedBox(height: 20),
          if (_step == 0) ...[
            Text(_text('Step 1：输入 6 位激活码', 'Step 1: Enter activation code'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              ],
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: 'ABC123',
                filled: true,
                fillColor: const Color(0xFFF5FBFA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _validateCodeStep,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFF0E6A55),
              ),
              child: Text(_text('下一步', 'Next'), style: const TextStyle(fontSize: 22)),
            ),
          ] else if (_step == 1) ...[
            Text(_text('Step 2：验证成功', 'Step 2: Verified'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0E6A55))),
            const SizedBox(height: 8),
            Text(
              _text('激活码校验通过，请设置登录密码', 'Code accepted, please set your password'),
              style: const TextStyle(fontSize: 21),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: _text('新密码', 'New password'),
                filled: true,
                fillColor: const Color(0xFFF5FBFA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _goToFinalStep,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFF0E6A55),
              ),
              child: Text(_text('下一步', 'Next'), style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _step = 0;
                        _error = null;
                      });
                    },
              child: Text(_text('返回上一步', 'Back')),
            ),
          ] else ...[
            Text(_text('Step 3：完成设置并登录', 'Step 3: Finish and sign in'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              _text(
                '激活码：${_codeController.text.trim().toUpperCase()}\n密码已设置完成，点击下方按钮立即登录。',
                'Code: ${_codeController.text.trim().toUpperCase()}\nPassword is ready. Tap below to sign in.',
              ),
              style: const TextStyle(fontSize: 21),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _completeActivation,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFF0E6A55),
              ),
              child: _busy
                  ? const CircularProgressIndicator()
                  : Text(
                      _text('完成设置并登录', 'Finish and sign in'),
                      style: const TextStyle(fontSize: 22),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _step = 1;
                        _error = null;
                      });
                    },
              child: Text(_text('返回上一步', 'Back')),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 19)),
          ],
        ],
      ),
    );
  }
}
