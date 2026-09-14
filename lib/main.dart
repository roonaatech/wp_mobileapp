import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/change_password_screen.dart';
import 'services/attendance_service.dart';
import 'services/auth_service.dart';
import 'utils/ist_helper.dart';
import 'config/app_config.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize AppConfig (detects physical Android device vs emulator)
    await AppConfig.initialize();

    // Initialize timezone helper
    await ISTHelper.initialize();

    // Fetch and update timezone and format settings from backend
    try {
      final settings = await AuthService.fetchGlobalSettings();
      if (settings != null) {
        await ISTHelper.setTimezone(settings['application_timezone']!);
        await ISTHelper.setFormatSettings(
          settings['application_date_format']!,
          settings['application_time_format']!,
        );
        print('Settings initialized from backend: ${settings['application_timezone']}');
      } else {
        print('Using default timezone: ${ISTHelper.getTimezoneName()}');
      }
    } catch (e) {
      print('Error fetching settings, using defaults: $e');
    }

    // Suppress google_fonts asset loading errors (they'll fallback to bundled/system fonts)
    GoogleFonts.config.allowRuntimeFetching = false;
    
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      final exStr = details.exception.toString().toLowerCase();
      // Suppress google_fonts AssetManifest errors
      if (exStr.contains('assetmanifest.json') ||
          exStr.contains('google_fonts') ||
          exStr.contains('googlefonts')) {
        if (kDebugMode) {
          print('Google Fonts fallback: ${details.exception}');
        }
        return;
      }
      FlutterError.presentError(details);
      if (kDebugMode) {
        print('Flutter Error: ${details.exception}');
        print('Stack trace: ${details.stack}');
      }
    };
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProxyProvider<AuthService, AttendanceService>(
            create: (_) => AttendanceService(token: null),
            update: (context, auth, previous) => AttendanceService(token: auth.token),
          ),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stackTrace) {
    final errStr = error.toString().toLowerCase();
    // Suppress google_fonts AssetManifest errors
    if (errStr.contains('assetmanifest.json') ||
        errStr.contains('google_fonts') ||
        errStr.contains('googlefonts')) {
      if (kDebugMode) {
        print('Google Fonts fallback (uncaught): $error');
      }
      return;
    }
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack trace: $stackTrace');
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkPulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/change-password': (context) => const ChangePasswordScreen(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (ctx, authService, _) {
        if (authService.isAuth) {
          if (authService.mustChangePassword) {
            return const ChangePasswordScreen(isMandatory: true);
          }
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
