import 'dart:js_interop';

@JS('pickupMonitorCanInstall')
external bool _canInstall();

@JS('pickupMonitorPromptInstall')
external JSPromise<JSBoolean> _promptInstall();

class PwaInstallService {
  const PwaInstallService._();

  static bool get canInstall {
    try {
      return _canInstall();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> promptInstall() async {
    try {
      final accepted = await _promptInstall().toDart;
      return accepted.toDart;
    } catch (_) {
      return false;
    }
  }
}
