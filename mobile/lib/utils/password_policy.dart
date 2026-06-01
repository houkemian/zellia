enum PasswordStrength { weak, medium, strong }

bool isPasswordPolicyValid(String password) {
  final value = password.trim();
  if (value.length < 8) return false;
  return RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value);
}

PasswordStrength passwordStrengthOf(String password) {
  final value = password.trim();
  if (!isPasswordPolicyValid(value)) return PasswordStrength.weak;
  final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
  if (value.length >= 12 && hasSymbol) return PasswordStrength.strong;
  return PasswordStrength.medium;
}
