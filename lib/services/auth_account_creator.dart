import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class AuthAccountCreator {
  const AuthAccountCreator._();

  static Future<String> createAccount({
    required String email,
    required String password,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'account-creator-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instanceFor(app: app);

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    } finally {
      await auth.signOut();
      await app.delete();
    }
  }
}
