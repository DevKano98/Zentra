import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/call_record.dart';
import '../models/user_profile.dart';
import '../models/unified_call_entry.dart';
import '../screens/scam_map_screen.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();

  Future<Dio> get _dio async {
    final dio = await ApiClient().getDio();
    if (!dio.interceptors.any((i) => i is LogInterceptor)) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (o) => debugPrint(o.toString()),
      ));
    }
    return dio;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<UserProfile> registerUser({
    required String phoneNumber,
    required String name,
    required String city,
    required int urgencyThreshold,
    required String voiceLanguage,
    required String voiceGender,
  }) async {
    final dio = await _dio;
    final resp = await dio.post('/users/register', data: {
      'phone_number': phoneNumber,
      'name': name,
      'city': city,
      'urgency_threshold': urgencyThreshold,
      'ai_language': voiceLanguage,
      'ai_voice_gender': voiceGender,
    });
    final data = resp.data as Map<String, dynamic>;

    if (data['token'] != null) {
      await _storage.write(key: kStorageJwtToken, value: data['token'] as String);
    }

    final profile = UserProfile.fromJson(
      data['user'] as Map<String, dynamic>? ?? data,
    );
    await _storage.write(key: kStorageUserId, value: profile.userId);
    await _storage.write(key: kStorageUserName, value: profile.name);
    await _storage.write(key: kStorageUserCity, value: profile.city);
    return profile;
  }

  Future<UserProfile> loginUser({
    required String phone,
  }) async {
    final dio = await _dio;
    final resp = await dio.post('/users/login', data: {
      'phone_number': phone,
    });
    final data = resp.data as Map<String, dynamic>;

    if (data['token'] != null) {
      await _storage.write(key: kStorageJwtToken, value: data['token'] as String);
    }

    final profile = UserProfile.fromJson(
      data['user'] as Map<String, dynamic>? ?? data,
    );
    await _storage.write(key: kStorageUserId, value: profile.userId);
    return profile;
  }

  Future<UserProfile> getUserProfile(String userId) async {
    final dio = await _dio;
    final resp = await dio.get('/users/$userId');
    return UserProfile.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> updatePreferences({
    required String userId,
    required int urgencyThreshold,
    required String voiceLanguage,
    required String voiceGender,
    String? telegramChatId,
    String? fcmToken,
  }) async {
    final profile = UserProfile(
      userId: userId,
      name: '',
      city: '',
      urgencyThreshold: urgencyThreshold,
      voiceLanguage: voiceLanguage,
      voiceGender: voiceGender,
      telegramChatId: telegramChatId,
      fcmToken: fcmToken,
    );
    final dio = await _dio;
    await dio.put('/users/preferences/$userId', data: {
      'urgency_threshold': urgencyThreshold,
      'ai_language': voiceLanguage,
      'ai_voice_gender': voiceGender,
      'auto_block_scam': false,
      'telegram_alerts': telegramChatId != null,
      'fcm_token': fcmToken,
    });
  }

  // ── Calls ─────────────────────────────────────────────────────────────────

  Future<bool> checkScamDb(String phoneNumber) async {
    try {
      final dio = await _dio;
      final resp = await dio.get('/scam/check', queryParameters: {'number': phoneNumber});
      return (resp.data as Map<String, dynamic>)['is_scam'] == true;
    } catch (_) {
      return false;
    }
  }

  String? _lastSavedCallId;

  Future<CallRecord> saveCallRecord({
    required String callId,
    required String number,
    required String transcript,
    String? category,
    int? urgencyScore,
    int? durationSeconds,
    String? callOutcome,
  }) async {
    if (callId == _lastSavedCallId) {
      throw Exception('Record already saved for this callId');
    }
    _lastSavedCallId = callId;

    final userId = await _storage.read(key: kStorageUserId) ?? '';
    final dio = await _dio;
    final resp = await dio.post('/calls/save-record', data: {
      'user_id': userId,
      'call_id': callId,
      'caller_number': number,
      'transcript': transcript.isNotEmpty ? transcript : 'No transcript recorded',
      'duration_seconds': durationSeconds ?? 0,
      'final_action': callOutcome ?? 'END_CALL',
      'final_category': category ?? 'UNKNOWN',
      'final_urgency': urgencyScore ?? 5,
    });
    return CallRecord.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> processCallTurn({
    required String callId,
    required String audioBase64,
    required String callerNumber,
    required String transcriptTurn,
    required List<Map<String, String>> conversationHistory,
  }) async {
    final userId = await _storage.read(key: kStorageUserId) ?? '';
    final dio = await _dio;
    final resp = await dio.post('/calls/process-turn', data: {
      'user_id': userId,
      'call_id': callId,
      'caller_number': callerNumber,
      'transcript_turn': transcriptTurn,
      'conversation_history': conversationHistory,
    });
    return resp.data as Map<String, dynamic>;
  }

// After:
Future<List<UnifiedCallEntry>> getCallHistory(String userId) async {
  if (userId.isEmpty) return [];
  final dio = await _dio;
  final resp = await dio.get('/calls/history/$userId');
  final list = resp.data as List;
  return list.map((e) => UnifiedCallEntry.fromApiJson(e as Map<String, dynamic>)).toList();
}
  Future<List<UnifiedCallEntry>> getRecentCalls({int limit = 3}) async {
    try {
      final userId = await _storage.read(key: kStorageUserId) ?? '';
      if (userId.isEmpty) return [];
      
      final dio = await _dio;
      final resp = await dio.get('/calls/recent/$userId');
      final list = resp.data as List;
      return list
          .map((e) => UnifiedCallEntry.fromApiJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, int>> getCallStats() async {
    try {
      final dio = await _dio;
      final resp = await dio.get('/dashboard/statistics');
      final data = resp.data as Map<String, dynamic>;
      return {
        'today': data['total_calls'] as int? ?? 0,
        'scams': data['scam_calls'] as int? ?? 0,
      };
    } catch (_) {
      return {'today': 0, 'scams': 0};
    }
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<CallRecord> generateFirReport(String callId) async {
    final dio = await _dio;
    final resp = await dio.post('/reports/generate-fir', data: {'call_id': callId});
    return CallRecord.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Returns the signed download URL for the FIR PDF.
  Future<String> downloadReport(String callId) async {
    final dio = await _dio;
    final resp = await dio.get('/reports/download/$callId');
    return (resp.data as Map<String, dynamic>)['signed_url'] as String? ?? '';
  }

  // ── Heatmap ───────────────────────────────────────────────────────────────

  Future<List<HeatmapPoint>> getScamHeatmap() async {
    final dio = await _dio;
    final resp = await dio.get('/dashboard/scam-heatmap');
    final list = resp.data as List;
    return list.map((e) => HeatmapPoint.fromJson(e as Map<String, dynamic>)).toList();
  }
}