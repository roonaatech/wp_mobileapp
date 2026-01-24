# Backend URL Configuration Guide

## Overview
All backend API URLs are now centralized in a single configuration file: `/lib/config/app_config.dart`

This means you only need to change the backend URL in **ONE place** instead of multiple service files.

## Quick Start

### For Local Development (flutter run)
```bash
flutter run
```
**Default:** Automatically connects to `localhost:3000`
- Android emulator: Uses `http://10.0.2.2:3000`
- iOS simulator: Uses `http://localhost:3000`

### For Building APK with Test Server
```bash
flutter build apk --debug --dart-define=USE_LOCALHOST=false
```
**Uses:** Test server `https://api.workpulse-uat.roonaa.in:3353`

### For Production Release
```bash
flutter build apk --release
```
**Uses:** Production server `https://api.workpulse-uat.roonaa.in:3353`

## How It Works

The app automatically selects the correct API endpoint based on:
1. **Build mode** (debug vs release)
2. **Platform** (Android emulator, iOS simulator, or physical device)
3. **Environment variable** `USE_LOCALHOST` (defaults to `true` for `flutter run`)

## URL Configuration

### Step 1: Open the Config File
```
/mobile_app/lib/config/app_config.dart
```

### Step 2: Available URL Constants

```dart
static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';           // Android Emulator
static const String _iosSimulatorUrl = 'http://localhost:3000';             // iOS Simulator
static const String _testServerUrl = 'https://api.workpulse-uat.roonaa.in:3353';  // Test/UAT Server
static const String _productionUrl = 'https://api.workpulse-uat.roonaa.in:3353';  // Production Server
```

## Environment Setup Details

### Android Emulator
```dart
static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
```
- Uses special IP `10.0.2.2` that Android emulator uses to reach host localhost
- Works with backend running on your machine
- Automatically used when running `flutter run` on Android emulator

### iOS Simulator
```dart
static const String _iosSimulatorUrl = 'http://localhost:3000';
```
- Uses `localhost` directly
- Works with backend running on your machine
- Automatically used when running `flutter run` on iOS simulator

### Test Server (UAT)
```dart
static const String _testServerUrl = 'https://api.workpulse-uat.roonaa.in:3353';
```
- Used for building debug APK for testing on physical devices
- Command: `flutter build apk --debug --dart-define=USE_LOCALHOST=false`

### Production Server
```dart
static const String _productionUrl = 'https://api.workpulse-uat.roonaa.in:3353';
```
- Used for release builds
- Command: `flutter build apk --release`
- Should use HTTPS (SSL/TLS)

## Advanced Usage

### Force Test Server During Development
If you want to test against the remote server while developing:
```bash
flutter run --dart-define=USE_LOCALHOST=false
```

### Custom Configuration for Physical Device
To test on a physical device with your local backend, update the URL:
```dart
static const String _physicalDeviceUrl = 'http://192.168.1.100:3000'; // Your computer's LAN IP
```

Find your LAN IP on macOS:
```bash
ifconfig | grep "inet " | grep -v "127.0.0.1"
```

Then modify the config logic to use this URL when `USE_LOCALHOST=true` but not on emulator.

## Using the Configuration

All services automatically use the correct URL based on platform and environment:

```dart
// In any service file, just import and use:
import '../config/app_config.dart';

// Then use the URLs like this:
final url = AppConfig.authSignIn;           // Login endpoint
final url = AppConfig.leaveApply;           // Apply leave
final url = AppConfig.onDutyStart;          // Start on-duty
final url = AppConfig.leaveHistory;         // Get history
// ... and more
```

## Available Endpoints

All endpoints are predefined in `AppConfig`:

### Authentication
- `AppConfig.authSignIn` - Login
- `AppConfig.authCheck` - Check auth status

### Leave Management
- `AppConfig.leaveApply` - Apply for leave
- `AppConfig.leaveHistory` - Get leave history
- `AppConfig.leaveDetail` - Get leave details (append ID)
- `AppConfig.leaveTypes` - Get leave types
- `AppConfig.leaveStats` - Get leave statistics

### On-Duty Management
- `AppConfig.onDutyStart` - Start on-duty
- `AppConfig.onDutyEnd` - End on-duty
- `AppConfig.onDutyActive` - Get active on-duty
- `AppConfig.onDutyDetail` - Get on-duty details (append ID)

## Example: Using with ID

When you need to append an ID to a URL:

```dart
// Instead of this (old way):
// final url = '${service._baseUrl}/$id';

// Do this (new way):
final url = '${AppConfig.leaveDetail}/$id';
final url = '${AppConfig.onDutyDetail}/$id';
```

## Current Service Files Using This Config

✅ `/lib/services/auth_service.dart` - Authentication
✅ `/lib/services/attendance_service.dart` - Leave & On-Duty endpoints

Both services now import and use `AppConfig` instead of having their own hardcoded URLs.

## Quick Reference

| Command | API Endpoint | Use Case |
|---------|--------------|----------|
| `flutter run` | `http://10.0.2.2:3000` (Android)<br>`http://localhost:3000` (iOS) | Local development with backend on your machine |
| `flutter run --dart-define=USE_LOCALHOST=false` | `https://api.workpulse-uat.roonaa.in:3353` | Test against remote server during development |
| `flutter build apk --debug --dart-define=USE_LOCALHOST=false` | `https://api.workpulse-uat.roonaa.in:3353` | Build debug APK for testing on physical devices |
| `flutter build apk --release` | `https://api.workpulse-uat.roonaa.in:3353` | Build production release APK |

## Configuration Logic

The `apiBaseUrl` getter uses this decision tree:

```
Is Release Mode?
├── Yes → Use Production URL
└── No (Debug Mode)
    └── USE_LOCALHOST flag set?
        ├── true (default for flutter run)
        │   ├── Android → http://10.0.2.2:3000
        │   └── iOS → http://localhost:3000
        └── false (for APK builds)
            └── Use Test Server URL
```

## Benefits of This Setup

✅ **Single Point of Change** - Update URL in one file  
✅ **No Hardcoding** - All URLs managed centrally  
✅ **Automatic Selection** - Right endpoint based on build mode and platform  
✅ **Easy Switching** - Use `--dart-define` flag to override defaults  
✅ **Type Safe** - Static constants prevent typos  
✅ **Maintainable** - Clear, documented endpoints  
✅ **Scalable** - Easy to add new endpoints  

## Troubleshooting

**Issue:** Connection refused on emulator
- **Solution:** Check backend is running on port 3000, verify `npm start` in backend directory

**Issue:** Still connecting to test server when running `flutter run`
- **Solution:** Hot restart the app (press `R` in terminal) or kill and restart `flutter run`

**Issue:** Connection refused on iOS
- **Solution:** Use `localhost` instead of `127.0.0.1`, backend must be on same machine

**Issue:** Need to test on physical device with local backend
- **Solution:** Find your computer's LAN IP and update `_androidEmulatorUrl` or `_iosSimulatorUrl` temporarily

**Issue:** SSL certificate errors
- **Solution:** Use HTTPS URL with proper SSL certificate on production

**Issue:** "Force Local" option in login not working
- **Solution:** This is a backend feature, not related to API URL configuration

## Testing Your Configuration

After updating or changing the configuration:

1. **Stop the app** completely (don't just hot reload)
2. **Run again:**
   ```bash
   flutter run
   ```
3. **Check the console logs** - You should see:
   ```
   Attempting login to: http://10.0.2.2:3000/api/auth/signin (Force Local: false)
   ```
4. **Verify the URL** matches your expectation
5. Test login to confirm backend connectivity

---

**That's it!** You now have a centralized, easy-to-manage backend URL configuration for your Flutter mobile app.
