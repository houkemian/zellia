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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.appBrand, style: theme.textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(l10n.loginTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _userController,
                decoration: InputDecoration(labelText: l10n.usernameLabel),
                textInputAction: TextInputAction.next,
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 18)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: _busy ? const CircularProgressIndicator() : Text(l10n.loginButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
