class UnifiedCallEntry {
  final String? contactName;
  final String number;
  final DateTime time;
  final int? durationSeconds;
  final bool wasAIScreened;
  final String? category;
  final int? urgencyScore;
  final String? transcript;
  final String? aiSummary;
  final String? firPdfUrl;
  final String? blockchainTxHash;
  final String? callOutcome;
  final String? callType; // INCOMING, OUTGOING, MISSED, REJECTED

  const UnifiedCallEntry({
    this.contactName,
    required this.number,
    required this.time,
    this.durationSeconds,
    required this.wasAIScreened,
    this.category,
    this.urgencyScore,
    this.transcript,
    this.aiSummary,
    this.firPdfUrl,
    this.blockchainTxHash,
    this.callOutcome,
    this.callType,
  });

  String get displayName => contactName ?? _maskedNumber;

  String get _maskedNumber {
    if (!wasAIScreened) return number;
    if (number.length <= 4) return number;
    final visible = number.substring(number.length - 4);
    return '••••••$visible';
  }

  String get fullNumber => number;

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '';
    final d = durationSeconds!;
    if (d < 60) return '${d}s';
    final m = d ~/ 60;
    final s = d % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  factory UnifiedCallEntry.fromDeviceLog(Map<String, dynamic> log) {
    return UnifiedCallEntry(
      contactName: log['name'] as String?,
      number: log['number'] as String? ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(log['timestamp'] as int? ?? 0),
      durationSeconds: log['duration'] as int?,
      wasAIScreened: false,
      callType: log['callType'] as String?,
    );
  }

  factory UnifiedCallEntry.fromApiJson(Map<String, dynamic> json) {
    return UnifiedCallEntry(
      contactName: json['contact_name'] as String?,
      number: json['number'] as String? ?? '',
      time: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      durationSeconds: json['duration_seconds'] as int?,
      wasAIScreened: true,
      category: json['category'] as String?,
      urgencyScore: json['urgency_score'] as int?,
      transcript: json['transcript'] as String?,
      aiSummary: json['ai_summary'] as String?,
      firPdfUrl: json['fir_pdf_url'] as String?,
      blockchainTxHash: json['blockchain_tx_hash'] as String?,
      callOutcome: json['call_outcome'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'contact_name': contactName,
        'number': number,
        'time': time.toIso8601String(),
        'duration_seconds': durationSeconds,
        'was_ai_screened': wasAIScreened,
        'category': category,
        'urgency_score': urgencyScore,
        'transcript': transcript,
        'ai_summary': aiSummary,
        'fir_pdf_url': firPdfUrl,
        'blockchain_tx_hash': blockchainTxHash,
        'call_outcome': callOutcome,
        'call_type': callType,
      };
}