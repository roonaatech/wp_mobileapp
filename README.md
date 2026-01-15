# ABiS WorkPulse Mobile App

An advanced Flutter-based employee management mobile application for effortless attendance tracking, leave management, and on-duty reporting.

## 🚀 Overview

**ABiS WorkPulse Mobile App** is designed to streamline workforce management by providing employees with a seamless mobile interface to manage their professional attendance and leave requests. The app integrates real-time location tracking for field duties and secure authentication to ensure data integrity.

## ✨ Key Features

- **🔐 Secure Authentication**: Token-based login system for authorized employees.
- **📅 Attendance Management**: 
    - Real-time punch-in/out.
    - View comprehensive attendance history.
- **📝 Leave Management**:
    - Apply for various leave types (Casual, Sick, etc.).
    - Track leave application status and history.
- **📍 On-Duty Reporting**:
    - Start and end on-duty activities with location tracking (`geolocator`).
    - Automated location capturing for field visits.
- **🔔 Real-time Updates**: Instant feedback on application status.
- **🛠 Configuration System**: Centralized API management for different environments (Development, Staging, Production).

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (v3.0+)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Networking**: [HTTP](https://pub.dev/packages/http)
- **Local Storage**: [Shared Preferences](https://pub.dev/packages/shared_preferences)
- **Location Services**: [Geolocator](https://pub.dev/packages/geolocator)
- **Typography & UI**: [Google Fonts](https://pub.dev/packages/google_fonts), Material 3

## 📁 Project Structure

```text
lib/
├── config/     # Centralized app configuration & API endpoints
├── models/     # Data models for Auth, Leave, and Attendance
├── screens/    # UI Screens (Login, Home, Leave, On-Duty)
├── services/   # Business logic & API service layers
├── utils/      # Constants and helper functions
└── main.dart   # App entry point & Provider setup
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Android Studio / VS Code
- A running instance of the **ABiS WorkPulse Backend**

### Configuration

Before running the app, ensure the backend URL is correctly configured:

1. Open `lib/config/app_config.dart`.
2. Update the base URL to match your environment (Emulator, Physical Device, or Production).
3. Refer to [CONFIG_GUIDE.md](file:///Users/sakthi/Documents/ABIS/WorkPulse/wp_mobileapp/CONFIG_GUIDE.md) for detailed setup instructions.

### Installation

```bash
# Clone the repository
git clone <repository-url>

# Navigate to the project directory
cd wp_mobileapp

# Get dependencies
flutter pub get

# Run the app
flutter run
```

---
