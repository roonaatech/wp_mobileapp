import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:attendance_app/screens/login_screen.dart';
import 'package:attendance_app/screens/home_screen.dart';
import 'package:attendance_app/services/auth_service.dart';
import 'package:attendance_app/services/attendance_service.dart';
import 'package:attendance_app/utils/ist_helper.dart';

void main() {
  setUpAll(() async {
    await ISTHelper.initialize();
  });
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

    // Verify Remember Me checkbox and Forgot Password button
    expect(find.text('Remember Me'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  testWidgets('Tapping Forgot Password navigates to ForgotPasswordScreen', (WidgetTester tester) async {
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

    // Tap Forgot Password?
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    // Verify ForgotPasswordScreen elements
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Send Temporary Password'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('HomeScreen displays only 4 nav items when canAccessAttendancePortal is false', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockAuth = MockAuthService(canAccessFace: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: mockAuth),
          ChangeNotifierProvider<AttendanceService>(create: (_) => AttendanceService(token: 'mock-token')),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify 4 tabs exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    expect(find.text('Time-Off'), findsOneWidget);
    expect(find.text('On-Duty'), findsOneWidget);
    // Attendance tab should NOT exist
    expect(find.text('Attendance'), findsNothing);
  });

  testWidgets('HomeScreen displays only Attendance option when canAccessAttendancePortal is true', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockAuth = MockAuthService(canAccessFace: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: mockAuth),
          ChangeNotifierProvider<AttendanceService>(create: (_) => AttendanceService(token: 'mock-token')),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify only Attendance exists and standard employee tabs do NOT exist
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Leave'), findsNothing);
    expect(find.text('Time-Off'), findsNothing);
    expect(find.text('On-Duty'), findsNothing);
  });
}

class MockAuthService extends ChangeNotifier implements AuthService {
  final bool _canAccessFace;
  MockAuthService({bool canAccessFace = false}) : _canAccessFace = canAccessFace;

  @override
  bool get canAccessAttendancePortal => _canAccessFace;

  @override
  String? get token => 'mock-token';

  @override
  String? get userId => '1';

  @override
  String? get userName => 'Test User';

  @override
  String? get userEmail => 'test@user.com';

  @override
  bool get isAuth => true;

  @override
  bool get mustChangePassword => false;

  @override
  String? get currentPassword => 'test';

  @override
  bool get isWorkPulseOnlyUser => false;

  @override
  bool get isServiceAccount => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
