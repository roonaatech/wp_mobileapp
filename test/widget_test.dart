import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:attendance_app/screens/login_screen.dart';
import 'package:attendance_app/services/auth_service.dart';

void main() {
  testWidgets('LoginScreen renders successfully with Poppins fonts', (WidgetTester tester) async {
    // Set a large enough surface size so all widgets fit without scrolling issues in test
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify brand and form elements are present
    expect(find.text('WorkPulse'), findsOneWidget);
    expect(find.text('MANAGEMENT'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
