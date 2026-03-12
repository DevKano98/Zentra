import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'constants.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

enum CallState { 
  idle, 
  incoming, // Screening AI
  active,   // Screening AI
  classifying, 
  completed, 
  ringing_normal, // Incoming normal
  outgoing,       // Outgoing normal (Dialing/Connecting)
  active_normal   // Ongoing normal
}

class CallSession {
  final String number;
  final String callId;
  final DateTime startTime;
  CallState state;
  String transcript;
  String? category;
  int? urgencyScore;
  String? aiSummary;

  CallSession({
    required this.number,
    required this.callId,
    required this.startTime,
    this.state = CallState.incoming,
    this.transcript = '',
    this.category,
    this.urgencyScore,
    this.aiSummary,
  });

  CallSession copyWith({
    CallState? state,
    String? transcript,
    String? category,
    int? urgencyScore,
    String? aiSummary,
  }) {
    return CallSession(
      number: number,
      callId: callId,
      startTime: startTime,
      state: state ?? this.state,
      transcript: transcript ?? this.transcript,
      category: category ?? this.category,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      aiSummary: aiSummary ?? this.aiSummary,
    );
  }
}

class CallManagerState {
  final CallState state;
  final CallSession? activeSession;
  final String liveTranscript;

  const CallManagerState({
    this.state = CallState.idle,
    this.activeSession,
    this.liveTranscript = '',
  });

  CallManagerState copyWith({
    CallState? state,
    CallSession? activeSession,
    String? liveTranscript,
  }) {
    return CallManagerState(
      state: state ?? this.state,
      activeSession: activeSession ?? this.activeSession,
      liveTranscript: liveTranscript ?? this.liveTranscript,
    );
  }
}

final callManagerProvider =
    NotifierProvider<CallManager, CallManagerState>(CallManager.new);

class CallManager extends Notifier<CallManagerState> {
  static const _audioChannel = MethodChannel(kChannelAudio);
  static const _callChannel = MethodChannel(kChannelCall);

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  final ApiService _api = ApiService();
  int _urgencyThreshold = kDefaultUrgencyThreshold;

  @override
  CallManagerState build() {
    return const CallManagerState();
  }

  Future<void> onIncomingScreeningCall(String number, String callId) async {
    if (state.state != CallState.idle) return;

    final session = CallSession(
      number: number,
      callId: callId,
      startTime: DateTime.now(),
      state: CallState.incoming,
    );

    state = state.copyWith(state: CallState.incoming, activeSession: session);

    // Open WebSocket for AI screening
    try {
      _wsChannel = await ApiClient().connectCallWebSocket(callId);
      state = state.copyWith(state: CallState.active);

      _wsSubscription = _wsChannel!.stream.listen(
        (message) => _onWebSocketMessage(message as String),
        onError: (error) => _onWebSocketError(error),
        onDone: () => _onWebSocketClosed(),
      );

      // Send call metadata
      _wsChannel!.sink.add(jsonEncode({
        'type': 'call_start',
        'number': number,
        'call_id': callId,
      }));
    } catch (e) {
      await endCall(reason: 'Connection error');
    }
  }

  Future<void> onIncomingCall(String number) async {
    final callId = DateTime.now().millisecondsSinceEpoch.toString();
    await onIncomingScreeningCall(number, callId);
  }

  Future<void> onCallStarted(String number, int androidState) async {
    // If we're already screening this number, stay in screening state
    if (state.state == CallState.incoming || state.state == CallState.active) {
       // Auto-answer if it's ringing and we're ready
       if (androidState == 2) { // STATE_RINGING
         await _callChannel.invokeMethod('answerCurrentCall');
       }
       return;
    }

    // Determine state
    CallState newState = CallState.ringing_normal;
    if (androidState == 1 || androidState == 9) { // DIALING or CONNECTING
       newState = CallState.outgoing;
    } else if (androidState == 2) { // RINGING
       newState = CallState.ringing_normal;
    }

    final session = CallSession(
      number: number,
      callId: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      state: newState,
    );
    state = state.copyWith(state: newState, activeSession: session);
  }

  Future<void> onCallActive() async {
    if (state.state == CallState.ringing_normal || state.state == CallState.outgoing) {
      state = state.copyWith(
        state: CallState.active_normal,
        activeSession: state.activeSession?.copyWith(state: CallState.active_normal),
      );
    }
  }

  Future<void> answerNormalCall() async {
    if (state.state != CallState.ringing_normal) return;
    try {
      await _callChannel.invokeMethod('answerCurrentCall');
      // State will be updated by onCallActive from native
    } catch (_) {}
  }

  Future<void> declineNormalCall() async {
    if (state.state == CallState.idle) return;
    await endCall(reason: 'Declined by user');
  }

  Future<void> onAudioChunk(Uint8List bytes) async {
    if (state.state != CallState.active) return;
    if (_wsChannel == null) return;

    _wsChannel!.sink.add(jsonEncode({
      'type': 'audio',
      'data': base64Encode(bytes),
    }));
  }

  Future<void> _onWebSocketMessage(String rawMessage) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(rawMessage) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final action = msg['action'] as String?;
    final transcriptDelta = msg['transcript_delta'] as String?;
    final aiAudioB64 = msg['ai_audio_b64'] as String?;
    final category = msg['category'] as String?;
    final urgencyScore = msg['urgency_score'] as int?;
    final aiSummary = msg['ai_summary'] as String?;

    // Append live transcript
    if (transcriptDelta != null && transcriptDelta.isNotEmpty) {
      final newTranscript =
          (state.activeSession?.transcript ?? '') + transcriptDelta;
      state = state.copyWith(
        liveTranscript: newTranscript,
        activeSession: state.activeSession?.copyWith(transcript: newTranscript),
      );
    }

    // Update classification
    if (category != null) {
      state = state.copyWith(
        activeSession: state.activeSession?.copyWith(
          category: category,
          urgencyScore: urgencyScore,
          aiSummary: aiSummary,
        ),
      );
    }

    // Play AI TTS audio into call
    if (aiAudioB64 != null && aiAudioB64.isNotEmpty) {
      final audioBytes = base64Decode(aiAudioB64);
      try {
        await _audioChannel.invokeMethod('playAudioBytes', {'data': audioBytes});
      } catch (_) {}
    }

    // Handle decisive actions
    if (action == kWsActionBlockOtp || action == kWsActionBlockScam) {
      await endCall(reason: 'AI blocked: $action');
    } else if (action == kWsActionRing) {
      // Let through to user — show notification
      final score = urgencyScore ?? 0;
      if (score >= _urgencyThreshold) {
        final number = state.activeSession?.number ?? '';
        final transcript = state.activeSession?.transcript ?? '';
        await NotificationService.instance.showCallNotification(
          callId: state.activeSession?.callId ?? '',
          number: number,
          category: category ?? 'UNKNOWN',
          transcriptPreview: transcript.length > 100
              ? transcript.substring(0, 100)
              : transcript,
          urgencyScore: score,
        );
      }
    }
  }

  void _onWebSocketError(dynamic error) {
    endCall(reason: 'WebSocket error');
  }

  void _onWebSocketClosed() {
    if (state.state == CallState.active) {
      endCall(reason: 'Connection closed');
    }
  }

  Future<void> onCallEnded() async {
    if (state.state == CallState.idle) return;
    await endCall(reason: 'Call ended by caller');
  }

  bool _isEnding = false;
  Future<void> endCall({String reason = ''}) async {
    if (_isEnding || state.state == CallState.idle) return;
    _isEnding = true;

    try {
    final session = state.activeSession;
    state = state.copyWith(state: CallState.classifying);

    // Close WebSocket
    await _wsSubscription?.cancel();
    await _wsChannel?.sink.close();
    _wsSubscription = null;
    _wsChannel = null;

    // Disconnect call in Android
    try {
      await _callChannel.invokeMethod('endCurrentCall');
    } catch (_) {}

    if (session != null) {
      // Save record to backend
      try {
        await _api.saveCallRecord(
          callId: session.callId,
          number: session.number,
          transcript: session.transcript,
          category: session.category,
          urgencyScore: session.urgencyScore,
          durationSeconds:
              DateTime.now().difference(session.startTime).inSeconds,
        );

        // Generate FIR if scam
        if (session.category == 'SCAM') {
          await _api.generateFirReport(session.callId);
        }
      } catch (_) {}
    }

    } finally {
      state = const CallManagerState(state: CallState.idle);
      _isEnding = false;
    }
  }

  void setUrgencyThreshold(int threshold) {
    _urgencyThreshold = threshold;
  }
}