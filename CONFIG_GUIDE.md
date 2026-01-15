# Backend URL Configuration Guide

## Overview
All backend API URLs are now centralized in a single configuration file: `/lib/config/app_config.dart`

This means you only need to change the backend URL in **ONE place** instead of multiple service files.

## How to Change Backend URL

### Step 1: Open the Config File
```
/mobile_app/lib/config/app_config.dart
```

### Step 2: Update the URL for Your Environment

In the `AppConfig` class, you'll find these URL constants:

```dart
static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';    // Android Emulator
static const String _physicalDeviceUrl = 'http://10.2.1.113:3000';   // Physical Device
static const String _iosSimulatorUrl = 'http://localhost:3000';      // iOS Simulator
static const String _productionUrl = 'https://your_production_domain.com'; // Production
```

### Step 3: Choose Your Environment

**For Android Emulator (Default):**
```dart
static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
```

**For Physical Android Device:**
```dart
static const String _physicalDeviceUrl = 'http://192.168.1.100:3000'; // Your computer's LAN IP
```

**For iOS Simulator:**
```dart
static const String _iosSimulatorUrl = 'http://localhost:3000';
```

**For Production (HTTPS):**
```dart
static const String _productionUrl = 'https://your_domain.com:3000';
// or if using standard HTTPS port:
static const String _productionUrl = 'https://your_domain.com';
```

## Environment Setup

### Android Emulator
```dart
static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
```
- Uses special IP `10.0.2.2` that Android emulator uses to reach host localhost
- Works with backend running on your machine

### iOS Simulator
```dart
static const String _iosSimulatorUrl = 'http://localhost:3000';
```
- Uses `localhost` directly
- Works with backend running on your machine

### Physical Device (Same Network)
```dart
static const String _physicalDeviceUrl = 'http://192.168.1.100:3000';
```
- Replace `192.168.1.100` with your computer's actual LAN IP
- Find your LAN IP on macOS: 
  ```bash
  ifconfig | grep "inet " | grep -v "127.0.0.1"
  ```

### Production Server
```dart
static const String _productionUrl = 'https://your_domain.com:3000';
```
- Update with your actual domain
- Should use HTTPS (SSL/TLS)
- If backend runs on standard port 443, omit `:3000`

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

| Environment | URL | Use Case |
|-------------|-----|----------|
| Android Emulator | `http://10.0.2.2:3000` | Local development on Android emulator |
| iOS Simulator | `http://localhost:3000` | Local development on iOS simulator |
| Physical Device | `http://YOUR_LAN_IP:3000` | Testing on actual phone on same network |
| Production | `https://your_domain.com` | Live deployment |

## Benefits of This Setup

✅ **Single Point of Change** - Update URL in one file  
✅ **No Hardcoding** - All URLs managed centrally  
✅ **Easy Switching** - Change between environments quickly  
✅ **Type Safe** - Static constants prevent typos  
✅ **Maintainable** - Clear, documented endpoints  
✅ **Scalable** - Easy to add new endpoints  

## Troubleshooting

**Issue:** Connection refused on emulator
- **Solution:** Check backend is running, verify port 3000 is open

**Issue:** Connection refused on iOS
- **Solution:** Use `localhost` instead of `127.0.0.1`, backend must be on same machine

**Issue:** Connection refused on physical device
- **Solution:** Find correct LAN IP (`ifconfig`), ensure phone is on same WiFi network

**Issue:** SSL certificate errors
- **Solution:** Use HTTPS URL with proper SSL certificate on production

## Next Steps

After updating the backend URL in `AppConfig`:

1. Hot reload/restart the Flutter app
2. Test authentication (login page)
3. Verify API calls work in console logs
4. Check network tab in browser dev tools

---

**That's it!** You now have a centralized, easy-to-manage backend URL configuration for your Flutter mobile app.
