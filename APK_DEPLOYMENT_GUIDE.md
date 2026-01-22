# WorkPulse APK Deployment Guide

This guide provides step-by-step instructions for building a production APK and installing it on Android devices for internal distribution.

---

## Prerequisites

Before building the APK, ensure you have:

1. **Flutter SDK** installed and configured
2. **Android SDK** with build tools
3. **Java JDK 17** installed
4. Terminal/Command line access

Verify your setup:
```bash
flutter doctor
```

---

## Part 1: Building the Production APK

### Step 1: Navigate to the Mobile App Directory

```bash
cd /Users/sakthi/Documents/ABIS/WorkPulse/wp_mobileapp
```

### Step 2: Clean Previous Builds

```bash
flutter clean
```

### Step 3: Get Dependencies

```bash
flutter pub get
```

### Step 4: Build the Release APK

You have two options for building the APK:

#### Option A: Fat APK (Single APK for all architectures)
This creates one APK that works on all Android devices but is larger in size (~50-70MB):

```bash
flutter build apk --release
```

**Output location:** `build/app/outputs/flutter-apk/app-release.apk`

#### Option B: Split APKs by Architecture (Recommended)
This creates smaller APKs optimized for specific device architectures (~15-25MB each):

```bash
flutter build apk --release --split-per-abi
```

**Output location:** `build/app/outputs/flutter-apk/`
- `app-armeabi-v7a-release.apk` - For older 32-bit ARM devices
- `app-arm64-v8a-release.apk` - For modern 64-bit ARM devices (most common)
- `app-x86_64-release.apk` - For x86 devices (emulators, some tablets)

> **Recommendation:** For most modern Android phones, use `app-arm64-v8a-release.apk`

---

## Part 2: APK Signing (Optional but Recommended)

For internal distribution, the APK is signed with a debug key by default. For better security and to avoid "Unknown Developer" warnings, you can create a production signing key.

### Create a Keystore (One-time setup)

```bash
keytool -genkey -v -keystore ~/workpulse-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias workpulse
```

You'll be prompted to:
- Create a keystore password
- Enter your name, organization, city, state, country
- Create a key password

**⚠️ IMPORTANT:** Keep this keystore file and passwords safe! You'll need them for future updates.

### Configure Signing in the App

1. Create a file `android/key.properties`:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=workpulse
storeFile=/Users/sakthi/workpulse-release-key.jks
```

2. Update `android/app/build.gradle.kts` to use the keystore (add before `buildTypes`):

```kotlin
// Add at the top of the android block
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = java.util.Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Replace the signingConfigs section
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}

buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

---

## Part 3: Installing APK on Android Device

### Method 1: Direct USB Transfer

1. **Enable Developer Options on your Android device:**
   - Go to **Settings → About Phone**
   - Tap **Build Number** 7 times
   - You'll see "You are now a developer!"

2. **Enable USB Debugging:**
   - Go to **Settings → Developer Options**
   - Enable **USB Debugging**

3. **Enable Installation from Unknown Sources:**
   - Go to **Settings → Security** (or **Settings → Apps → Special Access**)
   - Enable **Install unknown apps** for your file manager

4. **Connect your phone via USB cable**

5. **Copy the APK to your device:**
   ```bash
   adb push build/app/outputs/flutter-apk/app-release.apk /sdcard/Download/
   ```
   
   Or manually copy the APK file to your phone's Download folder.

6. **Install the APK:**
   - Open **File Manager** on your phone
   - Navigate to **Download** folder
   - Tap on `app-release.apk`
   - Tap **Install**
   - If prompted about security, tap **Settings** and enable installation

### Method 2: Using ADB Install (Faster)

1. Connect your phone via USB with USB Debugging enabled

2. Verify device is connected:
   ```bash
   adb devices
   ```

3. Install directly via ADB:
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

   For reinstallation (keeping app data):
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

### Method 3: Share via Network/Email

1. Upload the APK to a file sharing service (Google Drive, Dropbox, etc.)
2. Share the download link with users
3. Users download and install following the same "Unknown Sources" steps above

### Method 4: Internal Web Server

Host the APK on your internal network:

1. Place the APK on a web server accessible within your network
2. Share the URL: `http://your-internal-server/workpulse.apk`
3. Users can download directly from their phone browser

---

## Part 4: Troubleshooting

### "App not installed" Error

- **Cause:** Existing app with different signature
- **Solution:** Uninstall the existing app first:
  ```bash
  adb uninstall com.abis.workpulse
  ```

### "Parse Error" when installing

- **Cause:** APK architecture mismatch or corrupted file
- **Solution:** Use the fat APK (`flutter build apk --release`) or the correct architecture-specific APK

### App crashes on launch

- **Cause:** Usually a configuration issue
- **Solution:** Check logs:
  ```bash
  adb logcat | grep -i flutter
  ```

### "Install blocked" or Security Warning

- **Cause:** Installation from unknown sources is disabled
- **Solution:** Enable installation for the app you're using to install (File Manager, Chrome, etc.)

---

## Part 5: Distribution Checklist

Before distributing the APK:

- [ ] Test the APK on multiple devices
- [ ] Verify API endpoints are pointing to production server
- [ ] Confirm version number is updated in `pubspec.yaml`
- [ ] Test all app features (login, attendance, leave, on-duty)
- [ ] Check location permissions work correctly
- [ ] Verify the app icon displays correctly

---

## Quick Reference Commands

```bash
# Navigate to project
cd /Users/sakthi/Documents/ABIS/WorkPulse/wp_mobileapp

# Clean and rebuild
flutter clean && flutter pub get

# Build release APK (single file)
flutter build apk --release

# Build release APK (split by architecture)
flutter build apk --release --split-per-abi

# Check connected devices
adb devices

# Install APK via ADB
adb install build/app/outputs/flutter-apk/app-release.apk

# Reinstall (keep data)
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Uninstall existing app
adb uninstall com.abis.workpulse

# View logs
adb logcat | grep -i flutter
```

---

## App Information

| Property | Value |
|----------|-------|
| **App Name** | ABiS WorkPulse |
| **Package ID** | com.abis.workpulse |
| **Version** | 1.0.0 |
| **Build Number** | 1 |
| **Min Android Version** | Android 5.0 (API 21) |
| **Target Android Version** | Android 14 (API 34) |
| **Production API** | https://api.roonaa.in:3343 |

---

## Updating the App

For future updates:

1. Update the version in `pubspec.yaml`:
   ```yaml
   version: 1.1.0+2  # Major.Minor.Patch+BuildNumber
   ```

2. Build new APK:
   ```bash
   flutter clean && flutter pub get && flutter build apk --release
   ```

3. Distribute to users - they can install over the existing app (data will be preserved)

---

*Last updated: January 21, 2026*
