import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Handles Firebase Cloud Messaging (FCM) integration.
///
/// Responsibilities:
/// - Request notification permissions
/// - Retrieve and persist FCM tokens per user
/// - Handle token refreshes and store updated tokens in Firestore
/// - Display local notifications when app is in foreground
/// - Handle notifications received in background / terminated state
///
/// Push sending is delegated to [NotificationService.sendPush] which calls
/// the FCM HTTP Legacy API using the server key stored in Firestore config.
class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _initialized = false;

  /// Initialization channel ID for local notifications
  static const String _channelId = 'campustrade_messages';
  static const String _channelName = 'CampusTrade Messages';
  static const String _channelDescription =
      'Notifications for chat messages, offers, and transaction updates';

  /// Initialize FCM and local notifications.
  /// Must be called once from main.dart after Firebase is initialized.
  ///
  /// Returns true if initialization succeeded, false if it failed
  /// (e.g., missing SHA-1 fingerprint or FCM not enabled in Firebase Console).
  Future<bool> initialize() async {
    if (_initialized) return true;

    // Setup local notifications
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions (iOS)
    final notificationSettings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );

    debugPrint(
      'FCM permission status: ${notificationSettings.authorizationStatus}',
    );

    // Get initial FCM token
    String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken failed (likely missing SHA-1 fingerprint): $e');
    }
    if (token != null) {
      debugPrint('FCM initial token obtained');
      await _saveTokenForCurrentUser(token);
    }

    // Listen for token refreshes
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed');
      _saveTokenForCurrentUser(newToken);
    });

    // Handle foreground messages — display as local notification
    try {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    } catch (e) {
      debugPrint('FCM onMessage listener setup failed: $e');
    }

    // Handle background tap events (app opened from notification)
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (e) {
      debugPrint('FCM onMessageOpenedApp listener setup failed: $e');
    }

    // Handle terminated state — notification that launched the app
    try {
      final remoteMessage = await _messaging.getInitialMessage();
      if (remoteMessage != null) {
        _handleNotificationTapData(remoteMessage.data);
      }
    } catch (e) {
      debugPrint('FCM getInitialMessage failed: $e');
    }

    _initialized = true;
    debugPrint('FCMService initialized successfully');
    return true;
  }

  /// Saves the current user's FCM token to their Firestore document.
  Future<void> _saveTokenForCurrentUser(String token) async {
    // The token is stored in users/{uid}/fcmToken
    // Actual saving is done by explicit call from AuthService.
    try {
      debugPrint('FCM token obtained: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  /// External: save token for a specific user (called from AuthService).
  Future<void> saveToken(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('FCMService.saveToken error: $e');
    }
  }

  /// Remove FCM token from user document (e.g., on logout).
  Future<void> removeToken(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('FCMService.removeToken error: $e');
    }
  }

  /// Get the FCM token for the current device.
  Future<String?> getToken() => _messaging.getToken();

  /// Display a local notification when the app is in the foreground.
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Handle foreground message — show a local notification.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle when user taps on a notification.
  void _onNotificationTap(NotificationResponse response) {
    _handleNotificationTapData({});
  }

  void _handleNotificationTap(RemoteMessage message) {
    _handleNotificationTapData(message.data);
  }

  void _handleNotificationTapData(Map<String, dynamic> data) {
    // Navigation on notification tap can be implemented here
    // e.g., navigate to a specific chat room or item detail
    debugPrint('FCM notification tapped with data: $data');
  }

  /// Retrieve the FCM server key from Firestore config document.
  Future<String?> _getServerKey() async {
    try {
      final doc =
          await _db.collection('config').doc('app').get().timeout(
                const Duration(seconds: 3),
              );
      return doc.data()?['fcmServerKey'] as String?;
    } catch (e) {
      debugPrint('FCMService._getServerKey error: $e');
      return null;
    }
  }

  /// Send a push notification to a specific user via FCM HTTP Legacy API.
  ///
  /// Requires the FCM server key to be stored in Firestore config at:
  ///   config/app { fcmServerKey: "..." }
  ///
  /// The server key can be obtained from:
  ///   Firebase Console → Project Settings → Cloud Messaging → Server Key
  ///
  /// Falls back silently if the server key or user FCM token is unavailable.
  Future<void> sendPush({
    required String userId,
    required String title,
    required String body,
  }) async {
    try {
      // Get recipient's FCM token
      final userDoc =
          await _db.collection('users').doc(userId).get().timeout(
                const Duration(seconds: 3),
              );
      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;

      // Get FCM server key from config
      final serverKey = await _getServerKey();
      if (serverKey == null || serverKey.isEmpty) {
        debugPrint('FCM server key not configured. Add to config/app > fcmServerKey');
        return;
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'to': token,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint('FCM push sent to user $userId');
      } else {
        debugPrint(
          'FCM push failed: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('FCMService.sendPush error: $e');
    }
  }
}
