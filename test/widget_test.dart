import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_monitor/main.dart';

void main() {
  testWidgets('shows the login entry flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Pickup Monitor'), findsOneWidget);
    expect(find.text('Core Features'), findsOneWidget);
    expect(find.text('QR Guardian Passes'), findsOneWidget);
    expect(find.text('Centralized Login'), findsOneWidget);
    expect(find.text('Continue to sign in'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue to sign in'));
    await tester.tap(find.text('Continue to sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('SECURE ACCESS'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
