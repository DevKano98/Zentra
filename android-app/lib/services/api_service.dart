import 'package:dio/dio.dart';
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

  Future<Dio> get _dio async => ApiClient().getDio();

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<UserProfile> registerUser({
    required String name,
    required String city,
    required int urgencyThreshold,
    required String voiceLanguage,
    required String voiceGender,
  }) async {
    final dio = await _dio;
    final resp = await dio.post('/users/register', data: {
      'name': name,
      'city': city,
      'urgency_threshold': urgencyThreshold,
      'voice_language': voiceLanguage,
      'voice_gender': voiceGender,
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
    required String otp,
  }) async {
    final dio = await _dio;
    final resp = await dio.post('/users/login', data: {'phone': phone, 'otp': otp});
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
    await dio.put('/users/preferences', data: {
      'user_id': userId,
      ...profile.toPreferencesJson(),
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

  Future<CallRecord> saveCallRecord({
    required String callId,
    required String number,
    required String transcript,
    String? category,
    int? urgencyScore,
    int? durationSeconds,
    String? callOutcome,
  }) async {
    final userId = await _storage.read(key: kStorageUserId) ?? '';
    final dio = await _dio;
    final resp = await dio.post('/calls/save-record', data: {
      'call_id': callId,
      'user_id': userId,
      'number': number,
      'transcript': transcript,
      'category': category,
      'urgency_score': urgencyScore,
      'duration_seconds': durationSeconds,
      'call_outcome': callOutcome,
    });
    return CallRecord.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> processCallTurn({
    required String callId,
    required String audioBase64,
  }) async {
    final dio = await _dio;
    final resp = await dio.post('/calls/process-turn', data: {
      'call_id': callId,
      'audio': audioBase64,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<List<CallRecord>> getCallHistory(String userId) async {
    final dio = await _dio;
    final resp = await dio.get('/calls/history/$userId');
    final list = resp.data as List;
    return list.map((e) => CallRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<UnifiedCallEntry>> getRecentCalls({int limit = 3}) async {
    try {
      final dio = await _dio;
      final resp = await dio.get('/calls/recent', queryParameters: {'limit': limit});
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
      final resp = await dio.get('/calls/stats');
      final data = resp.data as Map<String, dynamic>;
      return {
        'today': data['calls_today'] as int? ?? 0,
        'scams': data['scams_blocked'] as int? ?? 0,
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