import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/brand_logo.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';
import '../utils/ist_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _isLoading = false;
  bool _rememberMe = false;
  String _versionInfo = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool('remember_me') ?? false;
      if (remember) {
        final email = prefs.getString('saved_email') ?? '';
        final password = prefs.getString('saved_password') ?? '';
        if (mounted) {
          setState(() {
            _rememberMe = true;
            if (email.isNotEmpty) _emailController.text = email;
            if (password.isNotEmpty) _passwordController.text = password;
          });
        }
      }
    } catch (e) {
      print("Error loading saved credentials: $e");
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionInfo = "v${info.version} (${info.buildNumber})";
        });
      }
    } catch (e) {
      print("Error loading version: $e");
    }
  }

  Future<void> _submit({bool forceLocal = false}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await Provider.of<AuthService>(context, listen: false).login(
        _emailController.text,
        _passwordController.text,
        forceLocal: forceLocal,
      );

      // Refresh application settings (timezone, etc) immediately after login
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final settings = await AuthService.fetchGlobalSettings(token: authService.token);
        if (settings != null) {
          await ISTHelper.setTimezone(settings['application_timezone']!);
          await ISTHelper.setFormatSettings(
            settings['application_date_format']!,
            settings['application_time_format']!,
          );
          print('Settings refreshed after login');
        }
      } catch (e) {
        print('Error refreshing settings after login: $e');
      }

      // Persist or clear Remember Me credentials based on user preference
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setBool('remember_me', true);
          await prefs.setString('saved_email', _emailController.text.trim());
          await prefs.setString('saved_password', _passwordController.text);
        } else {
          await prefs.setBool('remember_me', false);
          await prefs.remove('saved_email');
          await prefs.remove('saved_password');
        }
      } catch (e) {
        print('Error saving credentials preference: $e');
      }

      // Navigation is handled by AuthWrapper in main.dart
    } catch (error) {
      final errorMessage = error.toString();
      
      if (error is AuthConfirmationException) {
         _showConfirmationDialog(context, error.message);
      } else if (error is AuthSetupRequiredException) {
         _showWelcomeDialog(context);
      } else if (error is AuthDeclarationRequiredException) {
         _showDeclarationRequiredDialog(context);
      } else if (error is AuthPasswordSetupRequiredException) {
         _showPasswordSetupRequiredDialog(context);
      } else if (error is AppUpdateRequiredException) {
         _showUpdateRequiredDialog(context, error);
      } else if (errorMessage.toLowerCase().contains("inactive")) {
        _showInactiveDialog(context);
      } else {
        String displayMessage = errorMessage.replaceAll('Exception: ', '').trim();
        if (displayMessage.toLowerCase().contains('user not found')) {
          displayMessage = 'User not found. Please check your email or contact your administrator.';
        } else if (displayMessage.toLowerCase().contains('connection refused') ||
                   displayMessage.toLowerCase().contains('socketexception')) {
          displayMessage = 'Unable to connect to server. Please verify the backend server is running.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayMessage,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE11D48),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showConfirmationDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade100, width: 2),
                ),
                child: const Text(
                  '🛡️',
                  style: TextStyle(fontSize: 32),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Authentication Update',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: const [
                    Text(
                      'We noticed a delay in reaching the primary directory server. This sometimes happens due to routine maintenance.',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Good news: You can still log in securely!',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your local account is ready to go. Would you like to proceed with local sign-in?',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                         Navigator.of(ctx).pop();
                         setState(() { _isLoading = false; });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _submit(forceLocal: true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Yes, Log In',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWelcomeDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '👋',
                  style: TextStyle(fontSize: 40),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to WorkPulse!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "We're excited to have you on board.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Your profile setup is incomplete.\n\nPlease contact your administrator to configure your account before you can log in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() { _isLoading = false; });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Okay, Got it',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeclarationRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '✍️',
                  style: TextStyle(fontSize: 40),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Declaration Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "You must complete your onboarding declaration before you can use the mobile app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: const Text(
                  'Please log in to a web browser to complete and sign the declaration, then return to the mobile app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() { _isLoading = false; });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Okay, Got it',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordSetupRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '🔑',
                  style: TextStyle(fontSize: 40),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Password Setup Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "You must complete your password setup before you can use the mobile app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: const Text(
                  'Please log in using a web browser to change your temporary password to a permanent one, then return to the mobile app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() { _isLoading = false; });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Okay, Got it',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpdateRequiredDialog(BuildContext context, AppUpdateRequiredException error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange.shade100, width: 2),
                ),
                child: const Text(
                  '📲',
                  style: TextStyle(fontSize: 32),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Update Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'A new version of WorkPulse is available!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text(
                              'Your Version',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'v${error.currentVersion}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            Text(
                              'Latest Version',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'v${error.latestVersion}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (error.releaseNotes != null && error.releaseNotes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        "What's New:",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        error.releaseNotes!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Please update to continue using the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final url = Uri.parse(error.downloadUrl);
                    print('Attempting to open download URL: ${error.downloadUrl}');
                    try {
                      // Try to launch directly - don't rely on canLaunchUrl which can be unreliable
                      final launched = await launchUrl(
                        url, 
                        mode: LaunchMode.externalApplication,
                      );
                      if (!launched && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not open download link. Please download manually from: ${error.downloadUrl}'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 8),
                          ),
                        );
                      }
                    } catch (e) {
                      print('Error launching URL: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error opening download: $e. URL: ${error.downloadUrl}'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 8),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text(
                    'Download Update',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() { _isLoading = false; });
                },
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInactiveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.shade100, width: 2),
                ),
                child: const Text(
                  '🚫',
                  style: TextStyle(fontSize: 32),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Account Inactive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your account is currently inactive.\nYou cannot access WorkPulse.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please contact your administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Background Layer 1: Corporate HR Workforce Imagery
          Positioned.fill(
            child: Image.asset(
              'assets/login_hr_bg.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),

          // Background Layer 2: Soft White Luminous Frosted Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withAlpha(240),
                    Colors.white.withAlpha(245),
                    Colors.white.withAlpha(250),
                  ],
                ),
              ),
            ),
          ),

          // Background Layer 3: Soft ambient radial glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x144F46E5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Interactive Scroll Area
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Brand Header Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Brand Logo & Typography
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const BrandLogo(size: 48),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [
                                        Color(0xFF2563EB),
                                        Color(0xFF4F46E5),
                                        Color(0xFF9333EA),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
                                    blendMode: BlendMode.srcIn,
                                    child: const Text(
                                      'WorkPulse',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.8,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'MANAGEMENT',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF334155),
                                      letterSpacing: 2.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Portal Version Status Chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(242),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE0E7FF), width: 1.2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A0F172A),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _versionInfo.isNotEmpty
                                      ? 'v${_versionInfo.split(' ').first.replaceAll('v', '')}'
                                      : 'v${AppConfig.appVersion}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF312E81),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Floating Card Container (Inverse Dark Color: Midnight Slate-900, High Contrast)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF334155), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withAlpha(100),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withAlpha(50),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Card Header: Sparkle Tag, Title & Subtitle
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1B4B),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF4338CA).withAlpha(120), width: 1.0),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 12,
                                      color: Color(0xFF818CF8),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'HUMAN RESOURCES & WORKFORCE',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFA5B4FC),
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            const Center(
                              child: Text(
                                'Employee Login',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),

                            const SizedBox(height: 4),

                            const Center(
                              child: Text(
                                'Sign in to access your attendance & HR workspace',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),

                            const SizedBox(height: 22),

                            // Form Fields
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Email Field Label
                                  const Text(
                                    'WORK EMAIL ADDRESS',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFCBD5E1),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'name@company.com',
                                      hintStyle: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.mail_outline_rounded,
                                        color: Color(0xFF94A3B8),
                                        size: 20,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.2),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2.0),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2.0),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 16),

                                  // Password Field Label
                                  const Text(
                                    'PASSWORD',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFCBD5E1),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Enter your password',
                                      hintStyle: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        color: Color(0xFF94A3B8),
                                        size: 20,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.2),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2.0),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2.0),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Password is required';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 12),

                                  // Remember Me & Forgot Password Row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Remember Me
                                      InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          setState(() {
                                            _rememberMe = !_rememberMe;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: Checkbox(
                                                  value: _rememberMe,
                                                  activeColor: const Color(0xFF6366F1),
                                                  checkColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  side: const BorderSide(color: Color(0xFF64748B), width: 1.5),
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _rememberMe = val ?? false;
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Remember me',
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: Color(0xFFCBD5E1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Forgot Password
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () async {
                                          final returnedEmail = await Navigator.of(context).push<String>(
                                            MaterialPageRoute(
                                              builder: (_) => ForgotPasswordScreen(
                                                initialEmail: _emailController.text.trim(),
                                              ),
                                            ),
                                          );
                                          if (returnedEmail != null && returnedEmail.isNotEmpty && mounted) {
                                            setState(() {
                                              _emailController.text = returnedEmail;
                                              _passwordController.clear();
                                            });
                                          }
                                        },
                                        child: const Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF818CF8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 20),

                                  // Gradient Action Button (Signature WorkPulse Gradient)
                                  Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      onTap: _isLoading ? null : _submit,
                                      borderRadius: BorderRadius.circular(14),
                                      child: Ink(
                                        height: 52,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF2563EB),
                                              Color(0xFF4F46E5),
                                              Color(0xFF9333EA),
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x604F46E5),
                                              blurRadius: 18,
                                              offset: Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                )
                                              : const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      'SIGN IN TO WORKPULSE',
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.white,
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Icon(
                                                      Icons.arrow_forward_rounded,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Secondary Info: HR Admin Help
                      Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            children: [
                              TextSpan(text: 'Are you new? '),
                              TextSpan(
                                text: 'Contact your HR Administrator',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF312E81),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Feature Chip: Dynamic QR Ready
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(235),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x080F172A),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 15,
                                color: Color(0xFF4F46E5),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Dynamic QR Attendance Ready',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Environment Badge and Version
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (AppConfig.envLabel != 'PROD')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Color(AppConfig.envColorValue),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                AppConfig.envLabel,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Opacity(
                            opacity: 0.65,
                            child: Text(
                              _versionInfo.isNotEmpty ? _versionInfo : 'v${AppConfig.appVersion} (${AppConfig.appBuild})',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Security & Encrypted Footer
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: Color(0xFF059669),
                          ),
                          SizedBox(width: 5),
                          Text(
                            '256-Bit Encrypted • Aayi Technologies Pvt Ltd',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      Center(
                        child: Text(
                          '© ${DateTime.now().year} WorkPulse • All rights reserved',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
