import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

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
    final email = _userController.text.trim();
    final password = _passController.text;

    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = _text('请输入有效邮箱地址', 'Please enter a valid email address.'));
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
        'username': email,
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
                          _registerMode ? _text('邮箱注册', 'Sign Up with Email') : l10n.loginTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _registerMode
                              ? _text('请输入邮箱和密码完成注册', 'Create your account with email and password')
                              : _text('欢迎回来，请登录继续使用', 'Welcome back, sign in to continue'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6B64)),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _userController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: _registerMode ? _text('邮箱', 'Email') : l10n.usernameLabel,
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
