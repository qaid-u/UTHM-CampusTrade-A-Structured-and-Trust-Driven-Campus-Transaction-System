# UTHM CampusTrade Setup Guide

This guide explains how to set up and run the UTHM CampusTrade Flutter + Firebase application on a local development machine.

## 1. Requirements

- Flutter SDK installed and added to PATH
- Android Studio or VS Code with Flutter/Dart extensions
- Android Emulator or physical Android device
- Firebase project access
- Git
- Java JDK compatible with the Android Gradle plugin

Check Flutter setup:

```bash
flutter doctor
```

Fix any required Android toolchain or license issues:

```bash
flutter doctor --android-licenses
```

## 2. Clone The Repository

```bash
git clone <repository-url>
cd UTHM-CampusTrade-A-Structured-and-Trust-Driven-Campus-Transaction-System
```

## 3. Install Flutter Packages

```bash
flutter pub get
```

## 4. Firebase Setup

Create or open your Firebase project, then enable these services:

- Authentication
- Cloud Firestore
- Firebase Storage
- Cloud Messaging

For Authentication, enable Email/Password sign-in. The app maps a student ID to the email format:

```text
studentId@student.uthm.edu.my
```

## 5. Add Firebase Config Files

Download the Firebase Android config file from Firebase Console:

```text
android/app/google-services.json
```

If you are building for iOS later, also add:

```text
ios/Runner/GoogleService-Info.plist
```

Do not commit private Firebase config files if your project policy excludes them.

## 6. Deploy Firebase Rules

Install Firebase CLI if needed:

```bash
npm install -g firebase-tools
```

Log in and select the correct Firebase project:

```bash
firebase login
firebase use <firebase-project-id>
```

Deploy Firestore and Storage rules:

```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
```

## 7. Required Assets

Make sure these folders exist:

```text
assets/images/
assets/audio/
```

The app logo should be placed in:

```text
assets/images/uthm_campustrade_logo.png
```

Audio feedback files should be placed under:

```text
assets/audio/
```

If audio files are missing, the app is designed to continue without blocking the user flow.

## 8. Run The App

Start an emulator or connect a physical Android device, then run:

```bash
flutter run
```

If the emulator reports insufficient storage, wipe emulator data from Android Studio Device Manager or create a new emulator with more storage.

## 9. Build APK

For debug APK:

```bash
flutter build apk --debug
```

For release APK:

```bash
flutter build apk --release
```

Output location:

```text
build/app/outputs/flutter-apk/
```

## 10. Common Checks Before Demo

- Run `flutter analyze`
- Confirm Firebase config file exists
- Confirm Firestore rules are deployed
- Confirm Storage rules are deployed
- Confirm emulator has enough storage
- Test login with a buyer account and seller account
- Test item upload with camera/gallery image
- Test chat, offer, transaction completion, and review flow
- Test notifications with app open and in background

## 11. Troubleshooting

If the app opens blank:

```bash
flutter clean
flutter pub get
flutter run
```

If Android build files look corrupted:

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

If Firebase permission errors appear, redeploy both rules files and confirm the user is signed in.

If device notifications do not appear, confirm notification permission is granted on the Android device and Firebase Cloud Messaging is configured for the project.
