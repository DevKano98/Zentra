
enum CallCategory {
  scam,
  spam,
  telemarketing,
  otp,
  delivery,
  legitimate,
  unknown,
}

enum CallOutcome {
  blocked,
  transferred,
  voicemail,
  disconnected,
  unknown,
}

class CallRecord {
  final String callId;
  final String userId;
  final String number;
  final String? contactName;
  final DateTime startedAt;
  final int? durationSeconds;
  final CallCategory category;
  final CallOutcome outcome;
  final int? urgencyScore;
  final String? transcript;
  final String? aiSummary;
  final String? firPdfUrl;
  final String? blockchainTxHash;
  final bool wasAiScreened;
  final String? city;
  final double? lat;
  final double? lng;

  const CallRecord({
    required this.callId,
    required this.userId,
    required this.number,
    this.contactName,
    required this.startedAt,
    this.durationSeconds,
    this.category = CallCategory.unknown,
    this.outcome = CallOutcome.unknown,
    this.urgencyScore,
    this.transcript,
    this.aiSummary,
    this.firPdfUrl,
    this.blockchainTxHash,
    this.wasAiScreened = true,
    this.city,
    this.lat,
    this.lng,
  });

  String get displayNumber {
    if (!wasAiScreened || contactName != null) return number;
    if (number.length <= 4) return number;
    return '••••••${number.substring(number.length - 4)}';
  }

  String get displayName => contactName ?? displayNumber;

  bool get isScam => category == CallCategory.scam;
  bool get hasFir => firPdfUrl != null && firPdfUrl!.isNotEmpty;
  bool get hasBlockchain => blockchainTxHash != null && blockchainTxHash!.isNotEmpty;

  String get categoryLabel => category.name.toUpperCase();

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '';
    final d = durationSeconds!;
    if (d < 60) return '${d}s';
    final m = d ~/ 60;
    final s = d % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    return CallRecord(
      callId: json['call_id'] as String? ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      number: json['number'] as String? ?? '',
      contactName: json['contact_name'] as String?,
      startedAt: DateTime.tryParse(json['started_at'] as String? ??
              json['created_at'] as String? ?? '') ??
          DateTime.now(),
      durationSeconds: json['duration_seconds'] as int?,
      category: _parseCategory(json['category'] as String?),
      outcome: _parseOutcome(json['call_outcome'] as String?),
      urgencyScore: json['urgency_score'] as int?,
      transcript: json['transcript'] as String?,
      aiSummary: json['ai_summary'] as String?,
      firPdfUrl: json['fir_pdf_url'] as String?,
      blockchainTxHash: json['blockchain_tx_hash'] as String?,
      wasAiScreened: json['was_ai_screened'] as bool? ?? true,
      city: json['city'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'call_id': callId,
        'user_id': userId,
        'number': number,
        'contact_name': contactName,
        'started_at': startedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'category': categoryLabel,
        'call_outcome': outcome.name.toUpperCase(),
        'urgency_score': urgencyScore,
        'transcript': transcript,
        'ai_summary': aiSummary,
        'fir_pdf_url': firPdfUrl,
        'blockchain_tx_hash': blockchainTxHash,
        'was_ai_screened': wasAiScreened,
        'city': city,
        'lat': lat,
        'lng': lng,
      };

  CallRecord copyWith({
    String? callId,
    String? userId,
    String? number,
    String? contactName,
    DateTime? startedAt,
    int? durationSeconds,
    CallCategory? category,
    CallOutcome? outcome,
    int? urgencyScore,
    String? transcript,
    String? aiSummary,
    String? firPdfUrl,
    String? blockchainTxHash,
    bool? wasAiScreened,
    String? city,
    double? lat,
    double? lng,
  }) {
    return CallRecord(
      callId: callId ?? this.callId,
      userId: userId ?? this.userId,
      number: number ?? this.number,
      contactName: contactName ?? this.contactName,
      startedAt: startedAt ?? this.startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      category: category ?? this.category,
      outcome: outcome ?? this.outcome,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      transcript: transcript ?? this.transcript,
      aiSummary: aiSummary ?? this.aiSummary,
      firPdfUrl: firPdfUrl ?? this.firPdfUrl,
      blockchainTxHash: blockchainTxHash ?? this.blockchainTxHash,
      wasAiScreened: wasAiScreened ?? this.wasAiScreened,
      city: city ?? this.city,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  static CallCategory _parseCategory(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'SCAM':
        return CallCategory.scam;
      case 'SPAM':
        return CallCategory.spam;
      case 'TELEMARKETING':
        return CallCategory.telemarketing;
      case 'OTP':
        return CallCategory.otp;
      case 'DELIVERY':
        return CallCategory.delivery;
      case 'LEGITIMATE':
        return CallCategory.legitimate;
      default:
        return CallCategory.unknown;
    }
  }

  static CallOutcome _parseOutcome(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'BLOCKED':
        return CallOutcome.blocked;
      case 'TRANSFERRED':
        return CallOutcome.transferred;
      case 'VOICEMAIL':
        return CallOutcome.voicemail;
      case 'DISCONNECTED':
        return CallOutcome.disconnected;
      default:
        return CallOutcome.unknown;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CallRecord && other.callId == callId);

  @override
  int get hashCode => callId.hashCode;
}