import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../services/api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance._showFromRemoteMessage(message);
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();

  static const String _callAlertChannelId = 'call_alerts';
  static const String _scamAlertChannelId = 'scam_alerts';

  Future<void> initialize() async {
    // Android local notification channels
    const callChannel = AndroidNotificationChannel(
      _callAlertChannelId,
      'Call Alerts',
      description: 'AI screened call notifications',
      importance: Importance.high,
      playSound: true,
    );
    const scamChannel = AndroidNotificationChannel(
      _scamAlertChannelId,
      'Scam Alerts',
      description: 'Scam call alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(callChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(scamChannel);

    // Init plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Setup FCM
    await setupFCM();
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    // Handle action button taps: 'take_call' or 'dismiss'
    debugPrint('Notification tapped: $payload, action: ${response.actionId}');
  }

  Future<void> setupFCM() async {
    // Request permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get FCM token
      final token = await _fcm.getToken();
      if (token != null) {
        await _storage.write(key: kStorageFcmToken, value: token);

        // Register with backend
        final userId = await _storage.read(key: kStorageUserId) ?? '';
        if (userId.isNotEmpty) {
          try {
            await ApiService().updatePreferences(
              userId: userId,
              urgencyThreshold: kDefaultUrgencyThreshold,
              voiceLanguage: 'Hindi',
              voiceGender: 'Female',
              fcmToken: token,
            );
          } catch (_) {}
        }
      }

      // Token refresh
      _fcm.onTokenRefresh.listen((newToken) async {
        await _storage.write(key: kStorageFcmToken, value: newToken);
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((message) {
        _showFromRemoteMessage(message);
      });

      // Background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  }

  Future<void> showCallNotification({
    required String callId,
    required String number,
    required String category,
    required String transcriptPreview,
    required int urgencyScore,
  }) async {
    final catColor = kCategoryColors[category]?.value ?? 0xFF4F46E5;

    final androidDetails = AndroidNotificationDetails(
      _callAlertChannelId,
      'Call Alerts',
      channelDescription: 'AI screened call notifications',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(catColor),
      styleInformation: BigTextStyleInformation(
        transcriptPreview,
        htmlFormatBigText: false,
        contentTitle: '📞 $category call from ••••${number.length > 4 ? number.substring(number.length - 4) : number}',
        htmlFormatContentTitle: false,
      ),
      actions: const [
        AndroidNotificationAction(
          'take_call',
          '✅ Take Call',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'dismiss',
          '❌ Dismiss',
          cancelNotification: true,
        ),
      ],
    );

    await _localNotifications.show(
      callId.hashCode,
      '${kCategoryEmojis[category] ?? ''} $category call screened',
      transcriptPreview,
      NotificationDetails(android: androidDetails),
      payload: 'call:$callId',
    );
  }

  Future<void> showScamAlert(String number, String message) async {
    const androidDetails = AndroidNotificationDetails(
      _scamAlertChannelId,
      'Scam Alerts',
      channelDescription: 'High priority scam alerts',
      importance: Importance.max,
      priority: Priority.max,
      color: Colors.red,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications.show(
      number.hashCode,
      '🚨 Scam call blocked',
      message,
      const NotificationDetails(android: androidDetails),
      payload: 'scam:$number',
    );
  }

  Future<void> _showFromRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final isScam = data['category'] == 'SCAM';

    if (isScam) {
      await showScamAlert(
        data['number'] ?? '',
        notification.body ?? 'Scam call blocked',
      );
    } else {
      const androidDetails = AndroidNotificationDetails(
        _callAlertChannelId,
        'Call Alerts',
        importance: Importance.high,
        priority: Priority.high,
      );

      await _localNotifications.show(
        notification.hashCode,
        notification.title ?? 'Zentra',
        notification.body ?? '',
        const NotificationDetails(android: androidDetails),
      );
    }
  }
}