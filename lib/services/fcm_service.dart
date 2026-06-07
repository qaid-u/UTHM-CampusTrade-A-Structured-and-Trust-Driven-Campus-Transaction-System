import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../screens/chat_screen.dart';
import '../screens/item_detail_screen.dart';
import '../screens/premium_screen.dart';
import '../screens/transaction_history_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background FCM message received: ${message.messageId}');
}

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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;
  String? _lastSavedToken;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationMirrorSub;
  final Set<String> _mirroredNotificationIds = {};
  DateTime? _notificationMirrorStartedAt;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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

    await _configureAndroidNotifications();

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
      token = await getToken();
    } catch (e) {
      debugPrint('FCM getToken failed (likely missing SHA-1 fingerprint): $e');
    }
    if (token != null) {
      debugPrint('FCM initial token obtained');
      await _saveTokenForCurrentUser(token);
    }

    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      startNotificationMirror(currentUser.uid);
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

  Future<void> _configureAndroidNotifications() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.requestNotificationsPermission();
  }

  /// Saves the current user's FCM token to their Firestore document.
  Future<void> _saveTokenForCurrentUser(String token) async {
    if (_lastSavedToken == token) return;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await saveToken(user.uid, token);
        startNotificationMirror(user.uid);
      }
      _lastSavedToken = token;
      debugPrint('FCM token obtained: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  /// External: save token for a specific user (called from AuthService).
  Future<void> saveToken(String userId, String token) async {
    if (userId.isEmpty || token.isEmpty || _lastSavedToken == token) return;
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      });
      _lastSavedToken = token;
      startNotificationMirror(userId);
    } catch (e) {
      debugPrint('FCMService.saveToken error: $e');
    }
  }

  /// Remove FCM token from user document (e.g., on logout).
  Future<void> removeToken(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      });
      _lastSavedToken = null;
      await _notificationMirrorSub?.cancel();
      _notificationMirrorSub = null;
    } catch (e) {
      debugPrint('FCMService.removeToken error: $e');
    }
  }

  /// Get the FCM token for the current device.
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCMService.getToken error: $e');
      return null;
    }
  }

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
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  void startNotificationMirror(String userId) {
    if (userId.isEmpty || _notificationMirrorSub != null) return;

    _notificationMirrorStartedAt = DateTime.now();
    _notificationMirrorSub = _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(20)
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final doc = change.doc;
              if (!_mirroredNotificationIds.add(doc.id)) continue;

              final data = doc.data() ?? {};
              final createdAtRaw = data['createdAt'];
              DateTime? createdAt;
              if (createdAtRaw is Timestamp) {
                createdAt = createdAtRaw.toDate();
              }

              final startedAt = _notificationMirrorStartedAt;
              if (startedAt != null &&
                  createdAt != null &&
                  createdAt.isBefore(
                    startedAt.subtract(const Duration(seconds: 2)),
                  )) {
                continue;
              }

              final title = data['title']?.toString() ?? 'Notification';
              final body = data['body']?.toString() ?? '';
              if (title.trim().isEmpty && body.trim().isEmpty) continue;

              showLocalNotification(
                title: title,
                body: body,
                payload: jsonEncode({
                  'notificationId': doc.id,
                  'route': data['route']?.toString() ?? '',
                  'relatedId': data['relatedId']?.toString() ?? '',
                  'relatedType': data['relatedType']?.toString() ?? '',
                  'type': data['type']?.toString() ?? 'system',
                }),
              );
            }
          },
          onError: (e) {
            debugPrint('Notification mirror listener failed: $e');
          },
        );
  }

  /// Handle foreground message — show a local notification.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      final notificationId = message.data['notificationId']?.toString() ?? '';
      if (notificationId.isNotEmpty &&
          !_mirroredNotificationIds.add(notificationId)) {
        return;
      }
      showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle when user taps on a notification.
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) {
      _handleNotificationTapData({});
      return;
    }
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationTapData(data);
    } catch (_) {
      _handleNotificationTapData({});
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    _handleNotificationTapData(message.data);
  }

  void _handleNotificationTapData(Map<String, dynamic> data) {
    debugPrint('FCM notification tapped with data: $data');
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final route = data['route']?.toString() ?? '';
    final relatedId = data['relatedId']?.toString() ?? '';
    final notificationId = data['notificationId']?.toString() ?? '';

    if (notificationId.isNotEmpty) {
      _db
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true, 'readAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }

    switch (route) {
      case 'chat':
        if (relatedId.isEmpty) return;
        navigator.push(
          MaterialPageRoute(builder: (_) => ChatScreen(roomId: relatedId)),
        );
        break;
      case 'item':
        if (relatedId.isEmpty) return;
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(itemId: relatedId),
          ),
        );
        break;
      case 'transaction':
        navigator.push(
          MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
        );
        break;
      case 'premium':
        navigator.push(
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        break;
      default:
        break;
    }
  }

  /// Retrieve the FCM server key from Firestore config document.
  Future<String?> _getServerKey() async {
    try {
      final doc = await _db
          .collection('config')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 3));
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
    Map<String, String> data = const {},
  }) async {
    try {
      // Get recipient's FCM token
      final userDoc = await _db
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 3));
      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;

      // Get FCM server key from config
      final serverKey = await _getServerKey();
      if (serverKey == null || serverKey.isEmpty) {
        debugPrint(
          'FCM server key not configured. Add to config/app > fcmServerKey',
        );
        return;
      }

      final response = await http
          .post(
            Uri.parse('https://fcm.googleapis.com/fcm/send'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'key=$serverKey',
            },
            body: jsonEncode({
              'to': token,
              'notification': {'title': title, 'body': body},
              'data': {'click_action': 'FLUTTER_NOTIFICATION_CLICK', ...data},
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint('FCM push sent to user $userId');
      } else {
        debugPrint('FCM push failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('FCMService.sendPush error: $e');
    }
  }
}
