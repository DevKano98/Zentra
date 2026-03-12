import 'package:flutter/material.dart';

// Backend
const String kDefaultBackendUrl = 'https://zentra-backend-ofva.onrender.com';
const String kWsBaseUrl = 'wss://zentra-backend-ofva.onrender.com';
const String kWsCallPath = '/ws/call/';

// MethodChannel names
const String kChannelScreening = 'zentra/screening';
const String kChannelAudio = 'zentra/audio';
const String kChannelCall = 'zentra/call';
const String kChannelNotifications = 'zentra/notifications';
const String kChannelSetup = 'zentra/setup';

// SecureStorage keys
const String kStorageBackendUrl = 'backend_url';
const String kStorageJwtToken = 'jwt_token';
const String kStorageUserId = 'user_id';
const String kStorageUserName = 'user_name';
const String kStorageUserCity = 'user_city';
const String kStorageUrgencyThreshold = 'urgency_threshold';
const String kStorageVoiceLanguage = 'voice_language';
const String kStorageVoiceGender = 'voice_gender';
const String kStorageTelegramChatId = 'telegram_chat_id';
const String kStorageFcmToken = 'fcm_token';

// Call categories
enum CallCategory {
  scam,
  spam,
  telemarketing,
  otp,
  delivery,
  unknown,
  legitimate,
}

// Category display config
const Map<String, Color> kCategoryColors = {
  'SCAM': Color(0xFFDC2626),
  'SPAM': Color(0xFFEA580C),
  'TELEMARKETING': Color(0xFFD97706),
  'OTP': Color(0xFF0891B2),
  'DELIVERY': Color(0xFF059669),
  'UNKNOWN': Color(0xFF6B7280),
  'LEGITIMATE': Color(0xFF16A34A),
};

const Map<String, String> kCategoryEmojis = {
  'SCAM': '🚨',
  'SPAM': '📵',
  'TELEMARKETING': '📢',
  'OTP': '🔐',
  'DELIVERY': '📦',
  'UNKNOWN': '❓',
  'LEGITIMATE': '✅',
};

// Voice options
const List<String> kVoiceLanguages = ['Hindi', 'English'];
const List<String> kVoiceGenders = ['Female', 'Male'];

// Urgency
const int kDefaultUrgencyThreshold = 7;
const int kUrgencyMin = 1;
const int kUrgencyMax = 10;

// WebSocket actions
const String kWsActionBlockOtp = 'BLOCK_OTP';
const String kWsActionBlockScam = 'BLOCK_SCAM';
const String kWsActionRing = 'RING_PHONE';
const String kWsActionContinue = 'CONTINUE';

// Heatmap refresh interval
const Duration kHeatmapRefreshInterval = Duration(seconds: 60);

// Audio constants (must match Kotlin — DO NOT CHANGE)
const int kAudioRecordSampleRate = 16000;
const int kAudioPlaySampleRate = 22050;