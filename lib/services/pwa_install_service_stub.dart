class PwaInstallService {
  const PwaInstallService._();

  static bool get canInstall => false;

  static Future<bool> promptInstall() async => false;
}
