class UserProfile {
  final String userId;
  final String name;
  final String? phone;
  final String city;
  final int urgencyThreshold;
  final String voiceLanguage;
  final String voiceGender;
  final String? telegramChatId;
  final String? fcmToken;
  final DateTime? createdAt;
  final UserStats? stats;

  const UserProfile({
    required this.userId,
    required this.name,
    this.phone,
    required this.city,
    this.urgencyThreshold = 7,
    this.voiceLanguage = 'Hindi',
    this.voiceGender = 'Female',
    this.telegramChatId,
    this.fcmToken,
    this.createdAt,
    this.stats,
  });

  bool get hasTelegram =>
      telegramChatId != null && telegramChatId!.isNotEmpty;

  String get voiceCode {
    // Sarvam voice code: e.g. 'hi-IN-female', 'en-IN-male'
    final lang = voiceLanguage == 'Hindi' ? 'hi-IN' : 'en-IN';
    final g = voiceGender.toLowerCase();
    return '$lang-$g';
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      city: json['city'] as String? ?? '',
      urgencyThreshold: json['urgency_threshold'] as int? ?? 7,
      voiceLanguage: json['voice_language'] as String? ?? 'Hindi',
      voiceGender: json['voice_gender'] as String? ?? 'Female',
      telegramChatId: json['telegram_chat_id'] as String?,
      fcmToken: json['fcm_token'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      stats: json['stats'] != null
          ? UserStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
        'phone': phone,
        'city': city,
        'urgency_threshold': urgencyThreshold,
        'voice_language': voiceLanguage,
        'voice_gender': voiceGender,
        'telegram_chat_id': telegramChatId,
        'fcm_token': fcmToken,
        'created_at': createdAt?.toIso8601String(),
      };

  Map<String, dynamic> toPreferencesJson() => {
        'urgency_threshold': urgencyThreshold,
        'voice_language': voiceLanguage,
        'voice_gender': voiceGender,
        if (telegramChatId != null) 'telegram_chat_id': telegramChatId,
        if (fcmToken != null) 'fcm_token': fcmToken,
      };

  UserProfile copyWith({
    String? userId,
    String? name,
    String? phone,
    String? city,
    int? urgencyThreshold,
    String? voiceLanguage,
    String? voiceGender,
    String? telegramChatId,
    String? fcmToken,
    DateTime? createdAt,
    UserStats? stats,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      urgencyThreshold: urgencyThreshold ?? this.urgencyThreshold,
      voiceLanguage: voiceLanguage ?? this.voiceLanguage,
      voiceGender: voiceGender ?? this.voiceGender,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt ?? this.createdAt,
      stats: stats ?? this.stats,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserProfile && other.userId == userId);

  @override
  int get hashCode => userId.hashCode;
}

class UserStats {
  final int totalCallsScreened;
  final int scamsBlocked;
  final int otpsProtected;
  final int callsToday;
  final int scamsThisMonth;

  const UserStats({
    this.totalCallsScreened = 0,
    this.scamsBlocked = 0,
    this.otpsProtected = 0,
    this.callsToday = 0,
    this.scamsThisMonth = 0,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalCallsScreened: json['total_calls_screened'] as int? ?? 0,
      scamsBlocked: json['scams_blocked'] as int? ?? 0,
      otpsProtected: json['otps_protected'] as int? ?? 0,
      callsToday: json['calls_today'] as int? ?? 0,
      scamsThisMonth: json['scams_this_month'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_calls_screened': totalCallsScreened,
        'scams_blocked': scamsBlocked,
        'otps_protected': otpsProtected,
        'calls_today': callsToday,
        'scams_this_month': scamsThisMonth,
      };
}