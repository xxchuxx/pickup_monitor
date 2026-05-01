class InputValidators {
  const InputValidators._();

  static bool isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  }

  static bool isStrongEnoughPassword(String value) {
    return value.trim().length >= 6;
  }
}
