final _e164TanzaniaPhone = RegExp(r'^\+255[67][0-9]{8}$');

String normalizeTanzaniaPhone(String input) {
  final trimmed = input.trim();
  final cleaned = trimmed.startsWith('+')
      ? '+${trimmed.substring(1).replaceAll(RegExp(r'\D'), '')}'
      : trimmed.replaceAll(RegExp(r'\D'), '');

  if (_e164TanzaniaPhone.hasMatch(cleaned)) {
    return cleaned;
  }
  if (RegExp(r'^255[67][0-9]{8}$').hasMatch(cleaned)) {
    return '+$cleaned';
  }
  if (RegExp(r'^0[67][0-9]{8}$').hasMatch(cleaned)) {
    return '+255${cleaned.substring(1)}';
  }
  if (RegExp(r'^[67][0-9]{8}$').hasMatch(cleaned)) {
    return '+255$cleaned';
  }
  throw const FormatException('Invalid Tanzanian phone number');
}

bool isValidPin(String pin) => RegExp(r'^[0-9]{4}$').hasMatch(pin);

bool isWeakPin(String pin) {
  if (!isValidPin(pin)) return true;
  if ({'0000', '1111', '1234', '4321'}.contains(pin)) return true;
  return RegExp(r'^([0-9])\1{3}$').hasMatch(pin);
}
