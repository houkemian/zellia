import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/legal_document_screen.dart';

const _kLegalMuted = Color(0xFF8FA89E);

TextStyle get _legalBaseStyle => const TextStyle(
      fontSize: 11,
      height: 1.45,
      color: _kLegalMuted,
      fontWeight: FontWeight.w400,
    );

TextStyle get _legalLinkStyle => const TextStyle(
      fontSize: 11,
      height: 1.45,
      color: _kLegalMuted,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: _kLegalMuted,
    );

/// Small gray line with tappable Terms / Privacy links (paywall subscribe flow).
class SubscribeLegalConsentText extends StatefulWidget {
  const SubscribeLegalConsentText({
    super.key,
    required this.t,
  });

  final String Function(String zh, String en) t;

  @override
  State<SubscribeLegalConsentText> createState() =>
      _SubscribeLegalConsentTextState();
}

class _SubscribeLegalConsentTextState extends State<SubscribeLegalConsentText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => LegalDocumentScreen.openTerms(
            context,
            widget.t('服务条款', 'Terms of Service'),
          );
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => LegalDocumentScreen.openPrivacy(
            context,
            widget.t('隐私政策', 'Privacy Policy'),
          );
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LegalRichLine(
      prefix: widget.t(
        '确认购买即表示您同意我们的 ',
        'By subscribing, you agree to our ',
      ),
      termsLabel: widget.t('服务条款', 'Terms of Service'),
      middle: widget.t(' 与 ', ' and '),
      privacyLabel: widget.t('隐私政策', 'Privacy Policy'),
      suffix: widget.t('。', '.'),
      termsRecognizer: _termsRecognizer,
      privacyRecognizer: _privacyRecognizer,
    );
  }
}

/// Small gray line with tappable Terms / Privacy links (login / OAuth flow).
class LoginLegalConsentText extends StatefulWidget {
  const LoginLegalConsentText({
    super.key,
    required this.t,
  });

  final String Function(String zh, String en) t;

  @override
  State<LoginLegalConsentText> createState() => _LoginLegalConsentTextState();
}

class _LoginLegalConsentTextState extends State<LoginLegalConsentText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => LegalDocumentScreen.openTerms(
            context,
            widget.t('服务条款', 'Terms of Service'),
          );
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => LegalDocumentScreen.openPrivacy(
            context,
            widget.t('隐私政策', 'Privacy Policy'),
          );
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LegalRichLine(
      prefix: widget.t(
        '继续即表示您同意 Zellia 的 ',
        "By continuing, you agree to Zellia's ",
      ),
      termsLabel: widget.t('服务条款', 'Terms of Service'),
      middle: widget.t('，并已知晓 ', ' and acknowledge the '),
      privacyLabel: widget.t('隐私政策', 'Privacy Policy'),
      suffix: widget.t('。', '.'),
      termsRecognizer: _termsRecognizer,
      privacyRecognizer: _privacyRecognizer,
    );
  }
}

class _LegalRichLine extends StatelessWidget {
  const _LegalRichLine({
    required this.prefix,
    required this.termsLabel,
    required this.middle,
    required this.privacyLabel,
    required this.suffix,
    required this.termsRecognizer,
    required this.privacyRecognizer,
  });

  final String prefix;
  final String termsLabel;
  final String middle;
  final String privacyLabel;
  final String suffix;
  final TapGestureRecognizer termsRecognizer;
  final TapGestureRecognizer privacyRecognizer;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: _legalBaseStyle,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: termsLabel,
            style: _legalLinkStyle,
            recognizer: termsRecognizer,
          ),
          TextSpan(text: middle),
          TextSpan(
            text: privacyLabel,
            style: _legalLinkStyle,
            recognizer: privacyRecognizer,
          ),
          TextSpan(text: suffix),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
