import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';

const _kPrimary = Color(0xFF5EC397);
const _kPrimaryDark = Color(0xFF3FAE82);
const _kPrimaryLight = Color(0xFF9EDDC3);
const _kSurface = Color(0xFFF4FBF7);
const _kStroke = Color(0xFFBFDFD1);
const _kTextStrong = Color(0xFF214438);
const _kTextMuted = Color(0xFF5E8274);
const _kWarmFill = Color(0xFFEAF8F1);

enum _ThirdPartyProvider { google, microsoft }

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
  bool _obscurePassword = true;
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

  Future<void> _submitFirebaseProxyLogin(_ThirdPartyProvider provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final firebaseAuth = FirebaseAuth.instance;
      String? idToken;
      String? accessToken;
      String providerName;

      if (provider == _ThirdPartyProvider.google) {
        providerName = 'google';
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          return;
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
          accessToken: googleAuth.accessToken,
        );
        final firebaseCred = await firebaseAuth.signInWithCredential(credential);
        idToken = await firebaseCred.user?.getIdToken();
        accessToken = firebaseCred.credential?.accessToken;
      } else {
        providerName = 'microsoft';
        final oauthProvider = OAuthProvider('microsoft.com')
          ..setCustomParameters({'prompt': 'select_account'});
        UserCredential cred;
        if (kIsWeb) {
          try {
            cred = await firebaseAuth.signInWithPopup(oauthProvider);
          } on FirebaseAuthException catch (e) {
            if (_isMissingInitialStateError(code: e.code, message: e.message)) {
              // Clean stale auth state and retry once for storage/session edge cases.
              await firebaseAuth.signOut();
              cred = await firebaseAuth.signInWithPopup(oauthProvider);
            } else {
              rethrow;
            }
          }
        } else {
          cred = await firebaseAuth.signInWithProvider(oauthProvider);
        }
        idToken = await cred.user?.getIdToken();
        accessToken = cred.credential?.accessToken;
      }

      if (idToken == null || idToken.isEmpty) {
        setState(() {
          _error = _text(
            '第三方登录失败：未获取到有效令牌',
            'Third-party login failed: missing ID token.',
          );
        });
        return;
      }

      final appToken = await widget.api.firebaseProxyLogin(
        provider: providerName,
        idToken: idToken,
        accessToken: accessToken,
      );
      await widget.api.saveToken(appToken);
      widget.onLoggedIn();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (_isMissingInitialStateError(code: e.code, message: e.message)) {
          setState(() {
            _error = _text(
              'Microsoft 登录失败：浏览器会话状态丢失，请刷新页面后重试，并检查浏览器是否允许 Cookie/存储权限。',
              'Microsoft sign-in failed: missing initial state. Please refresh the page and ensure browser cookies/storage permissions are enabled.',
            );
          });
        } else {
          setState(() {
            _error = _text(
              '第三方登录失败：${e.message ?? e.code}',
              'Third-party login failed: ${e.message ?? e.code}',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        if (_isMissingInitialStateError(message: raw)) {
          setState(() {
            _error = _text(
              'Microsoft 登录失败：浏览器会话状态丢失，请刷新页面后重试，并检查浏览器是否允许 Cookie/存储权限。',
              'Microsoft sign-in failed: missing initial state. Please refresh the page and ensure browser cookies/storage permissions are enabled.',
            );
          });
          return;
        }
        setState(() {
          _error = _text(
            '第三方登录失败：$e',
            'Third-party login failed: $e',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isMissingInitialStateError({String? code, String? message}) {
    final normalizedCode = (code ?? '').toLowerCase();
    final normalizedMessage = (message ?? '').toLowerCase();
    return normalizedCode == 'missing-initial-state' ||
        normalizedMessage.contains('missing initial state') ||
        normalizedMessage.contains('missing-initial-state');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kPrimaryDark, _kPrimary, _kPrimaryLight],
              ),
            ),
            child: SizedBox.expand(),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _text('岁月安', 'Zellia'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset(
                              'assets/images/logo_with_name.png',
                              height: 86,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 14),
                            if (_registerMode) ...[
                              Text(
                                _text('创建账号', 'Create account'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _kTextStrong,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _text('注册后即可开始健康管理', 'Create your account to get started'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _kTextMuted, fontSize: 14),
                              ),
                              const SizedBox(height: 22),
                            ] else
                              const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _kWarmFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _ModeButton(
                                      active: !_registerMode,
                                      text: _text('登录', 'Sign in'),
                                      onTap: _busy ? null : () => _switchMode(false),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: _ModeButton(
                                      active: _registerMode,
                                      text: _text('注册', 'Sign up'),
                                      onTap: _busy ? null : () => _switchMode(true),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _userController,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: _text('账号 / 邮箱', 'Account / Email'),
                                prefixIcon: const Icon(Icons.person_outline_rounded),
                                filled: true,
                                fillColor: _kSurface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kStroke),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kStroke),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kPrimary, width: 1.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passController,
                              obscureText: _obscurePassword,
                              onSubmitted: (_) => _registerMode ? _submitRegister() : _submitLogin(),
                              decoration: InputDecoration(
                                labelText: l10n.passwordLabel,
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                ),
                                filled: true,
                                fillColor: _kSurface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kStroke),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kStroke),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: _kPrimary, width: 1.8),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6EBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD8B6B6)),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF7A4A4A)),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : (_registerMode ? _submitRegister : _submitLogin),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                backgroundColor: _kPrimary,
                                disabledBackgroundColor: _kPrimary.withValues(alpha: 0.55),
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shadowColor: const Color(0x5545A97F),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : Text(
                                      _registerMode ? _text('注册并登录', 'Sign up & sign in') : l10n.loginButton,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _openActivationWizard,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                side: const BorderSide(color: _kPrimary, width: 1.4),
                                backgroundColor: _kWarmFill,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.vpn_key_rounded, color: _kPrimary),
                              label: Text(
                                _text('使用亲情激活码', 'Use family activation code'),
                                style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(child: Divider(color: _kStroke)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    _text('或使用第三方登录', 'Or continue with'),
                                    style: const TextStyle(color: _kTextMuted, fontSize: 12),
                                  ),
                                ),
                                const Expanded(child: Divider(color: _kStroke)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _ThirdPartyLoginButton(
                              onPressed: _busy
                                  ? null
                                  : () => _submitFirebaseProxyLogin(_ThirdPartyProvider.google),
                              iconPath: 'assets/icons/google_logo.png',
                              text: _text('使用 Google 登录', 'Continue with Google'),
                            ),
                            const SizedBox(height: 10),
                            _ThirdPartyLoginButton(
                              onPressed: _busy
                                  ? null
                                  : () => _submitFirebaseProxyLogin(_ThirdPartyProvider.microsoft),
                              iconPath: 'assets/icons/microsoft_logo.png',
                              text: _text('使用 Microsoft 登录', 'Continue with Microsoft'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.active,
    required this.text,
    required this.onTap,
  });

  final bool active;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFFFF2E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? const Color(0xFF8ED0B5) : _kStroke),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x335EC397),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? _kTextStrong : _kTextMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ThirdPartyLoginButton extends StatelessWidget {
  const _ThirdPartyLoginButton({
    required this.onPressed,
    required this.iconPath,
    required this.text,
  });

  final VoidCallback? onPressed;
  final String iconPath;
  final String text;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: _kStroke, width: 1.2),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(iconPath, width: 20, height: 20, fit: BoxFit.contain),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: _kTextStrong,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0x5545A97F),
              ),
              child: Text(_text('下一步', 'Next'), style: const TextStyle(fontSize: 22)),
            ),
          ] else if (_step == 1) ...[
            Text(_text('Step 2：验证成功', 'Step 2: Verified'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _kPrimaryDark)),
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
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0x5545A97F),
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
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0x5545A97F),
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
