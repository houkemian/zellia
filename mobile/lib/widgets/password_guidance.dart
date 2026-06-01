import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../utils/password_policy.dart';

class PasswordGuidance extends StatelessWidget {
  const PasswordGuidance({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final strength = passwordStrengthOf(password);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.passwordPolicyHint,
          style: const TextStyle(
            fontSize: 16,
            height: 1.35,
            color: Color(0xFF5E8274),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.passwordStrengthLabel(_strengthText(l10n, strength)),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _strengthColor(strength),
          ),
        ),
      ],
    );
  }

  String _strengthText(AppLocalizations l10n, PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.weak => l10n.passwordStrengthWeak,
      PasswordStrength.medium => l10n.passwordStrengthMedium,
      PasswordStrength.strong => l10n.passwordStrengthStrong,
    };
  }

  Color _strengthColor(PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.weak => const Color(0xFFC62828),
      PasswordStrength.medium => const Color(0xFF8A5A00),
      PasswordStrength.strong => const Color(0xFF0E6A55),
    };
  }
}
