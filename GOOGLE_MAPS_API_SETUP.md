# 🔑 Google Maps API Key Setup Guide

## Step-by-Step Instructions

### 1. Get Your Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the following APIs:
   - ✅ **Maps SDK for Android** (Required)
   - ✅ **Maps SDK for iOS** (Required)
   - 🔧 **Places API** (Optional - for search autocomplete)
   - 🔧 **Directions API** (Optional - for navigation)
   - 🔧 **Geocoding API** (Optional - you're using free geocoding package)

4. Go to **Credentials** → **Create Credentials** → **API Key**
5. Copy your API key

### 2. Configure API Key for Android

#### Option A: Using local.properties (Recommended for Development)

Add this line to `android/local.properties`:
```properties
MAPS_API_KEY=YOUR_API_KEY_HERE
```

#### Option B: Using gradle.properties

Add this line to `android/gradle.properties`:
```properties
MAPS_API_KEY="YOUR_API_KEY_HERE"
```

#### Option C: Hardcode in AndroidManifest.xml (Not Recommended)

Replace `${MAPS_API_KEY}` in `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ACTUAL_API_KEY_HERE" />
```

### 3. Configure API Key for iOS

Edit `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import GoogleMaps  // Add this import

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_API_KEY_HERE")  // Add this line
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### 4. Add URL Scheme for Directions (iOS)

Edit `ios/Runner/Info.plist`:
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>comgooglemaps</string>
    <string>googlechromes</string>
</array>
```

### 5. Restrict Your API Key (Security)

In Google Cloud Console:
1. Go to **Credentials** → Select your API key
2. Under **Application restrictions**:
   - **Android**: Add your app's package name (`com.example.uthm_campustrade`) and SHA-1 certificate fingerprint
   - **iOS**: Add your app's bundle identifier
3. Under **API restrictions**:
   - Select **Restrict key**
   - Check only: Maps SDK for Android, Maps SDK for iOS

### 6. Test Your Setup

Run your app:
```bash
flutter run
```

Navigate to any screen with a map. If the map loads correctly, your API key is configured properly!

## 🆓 Free Tier Limits

- **Maps SDK for Android/iOS**: Unlimited (FREE)
- **Geocoding API**: 40,000 requests/month (FREE)
- **Places API**: 100,000 requests/month (FREE tier available)
- **Directions API**: 40,000 requests/month (FREE)

## 💡 Cost Optimization Tips

1. ✅ Use the free `geocoding` package (already implemented)
2. ✅ Use preset campus locations instead of Places API search
3. ✅ Open external Google Maps app for directions (no API call needed)
4. ✅ Cache location data in Firestore
5. ✅ Avoid unnecessary map reloads

## 🔒 Security Best Practices

- ✅ Never commit API keys to version control
- ✅ Use environment variables or local.properties
- ✅ Add `google-services.json` and API keys to `.gitignore`
- ✅ Set API key restrictions in Google Cloud Console
- ✅ Monitor usage in Google Cloud Console

## 📱 Required Permissions

### Android (Already configured)
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

### iOS (Add to Info.plist)
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to show meetup points on campus.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app uses your location to help you find safe meetup spots.</string>
```

## ❓ Troubleshooting

### Map shows blank screen
- Check API key is correct
- Verify Maps SDK is enabled in Google Cloud Console
- Check internet connection

### "Authorization failure" error
- API key restrictions may be too strict
- Check package name/bundle ID matches
- Verify SHA-1 fingerprint for Android

### Location not working
- Check location permissions are granted
- Verify GPS is enabled on device
- Test on physical device (emulator location may be inaccurate)

## 📞 Need Help?

- [Google Maps Platform Documentation](https://developers.google.com/maps)
- [google_maps_flutter Package](https://pub.dev/packages/google_maps_flutter)
- [Flutter Location Documentation](https://docs.flutter.dev/cookbook/device-location)
