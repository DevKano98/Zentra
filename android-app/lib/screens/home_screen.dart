import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/call_manager.dart';
import '../core/theme.dart';
import '../models/unified_call_entry.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';

final recentCallsProvider = FutureProvider<List<UnifiedCallEntry>>((ref) async {
  return ApiService().getRecentCalls();
});

final callStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ApiService().getCallStats();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.zentra.dialer/call_control');
  bool _isDefaultDialer = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDefaultDialer();
    
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingScreeningCall') {
        final number = call.arguments['caller_number'] as String;
        final callId = call.arguments['call_id'] as String;
        ref.read(callManagerProvider.notifier).onIncomingScreeningCall(number, callId);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDefaultDialer();
    }
  }

  Future<void> _checkDefaultDialer() async {
    try {
      final check = await _channel.invokeMethod('checkDefaultDialer');
      if (mounted) {
        setState(() => _isDefaultDialer = check == true);
      }
    } catch (_) {}
  }

  Future<void> _requestDefaultDialer() async {
    try {
      final result = await _channel.invokeMethod('setDefaultDialer');
      if (result == true && mounted) {
        setState(() => _isDefaultDialer = true);
      } else {
        await Future.delayed(const Duration(milliseconds: 1500));
        _checkDefaultDialer();
      }
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 1500));
      _checkDefaultDialer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callManagerProvider);
    final recentCalls = ref.watch(recentCallsProvider);
    final stats = ref.watch(callStatsProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kPurple,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.shield_rounded, color: kPurpleDeep, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Zentra'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (!_isDefaultDialer)
            GestureDetector(
              onTap: _requestDefaultDialer,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFFFEF2F2),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Zentra is not default dialer. AI screening is disabled. Tap to fix.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
                      ),
                    ),
                    TextButton(
                      onPressed: _requestDefaultDialer,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('FIX',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: kPurpleDeep,
              onRefresh: () async {
          ref.invalidate(recentCallsProvider);
          ref.invalidate(callStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // AI Protection Status Card
            _AIStatusCard(callState: callState),
            const SizedBox(height: 16),

            // Live transcript (active calls only)
            if (callState.state == CallState.active ||
                callState.state == CallState.incoming) ...[
              _LiveTranscriptCard(callState: callState),
              const SizedBox(height: 16),
            ],

            // Stats row
            stats.when(
              data: (s) => _StatsRow(
                callsToday: s['today'] ?? 0,
                scamsBlocked: s['scams'] ?? 0,
              ),
              loading: () => const _StatsRowSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Section header
            const Row(
              children: [
                Text(
                  'Recent Screened Calls',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                Spacer(),
                Icon(Icons.auto_awesome_rounded, size: 14, color: kPurpleDark),
                SizedBox(width: 4),
                Text(
                  'AI Protected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kPurpleDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            recentCalls.when(
              data: (calls) => calls.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: calls
                          .take(5)
                          .map((c) => _ScreenedCallCard(entry: c))
                          .toList(),
                    ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: SpinKitThreeBounce(
                    color: kPurpleDark,
                    size: 28,
                  ),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $err',
                    style: const TextStyle(color: kTextSecondary)),
              ),
            ),
          ],
        ),
      ),
    ),
  ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI Status Card
// ─────────────────────────────────────────────────────────────────────────────

class _AIStatusCard extends StatelessWidget {
  final CallManagerState callState;
  const _AIStatusCard({required this.callState});

  @override
  Widget build(BuildContext context) {
    final isActive = callState.state != CallState.idle;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? kPurple : kBorder,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? kPurple.withOpacity(0.18)
                : Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon area
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? kPurple.withOpacity(0.2) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: isActive
                ? const Center(
                    child: SpinKitPulse(
                      color: kPurpleDark,
                      size: 28,
                    ),
                  )
                : const Icon(Icons.shield_rounded,
                    color: kTextSecondary, size: 26),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'AI Screening Active' : 'AI Protection On',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isActive
                      ? _getStatusDescription(callState.state)
                      : 'Monitoring all incoming calls',
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
            ),
          ),

          // Status dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isActive ? kPurpleDark : Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isActive ? kPurpleDark : Colors.green)
                      .withOpacity(0.45),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusDescription(CallState state) {
    switch (state) {
      case CallState.incoming:
        return 'Incoming call detected…';
      case CallState.active:
        return 'Screening call in progress';
      case CallState.classifying:
        return 'Classifying caller…';
      default:
        return 'Processing';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Transcript Card
// ─────────────────────────────────────────────────────────────────────────────

class _LiveTranscriptCard extends StatelessWidget {
  final CallManagerState callState;
  const _LiveTranscriptCard({required this.callState});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPurple, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SpinKitWave(color: kPurpleDark, size: 14),
              const SizedBox(width: 8),
              const Text(
                'LIVE TRANSCRIPT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kPurpleDark,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                callState.activeSession?.number ?? '',
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 72,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                callState.liveTranscript.isEmpty
                    ? 'Listening…'
                    : callState.liveTranscript,
                style: const TextStyle(
                    fontSize: 13, color: kTextPrimary, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int callsToday;
  final int scamsBlocked;
  const _StatsRow({required this.callsToday, required this.scamsBlocked});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Calls Today',
            value: callsToday.toString(),
            icon: Icons.phone_rounded,
            accent: kPurple,
            iconColor: kPurpleDeep,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Scams Blocked',
            value: scamsBlocked.toString(),
            icon: Icons.block_rounded,
            accent: const Color(0xFFFFE4E4),
            iconColor: const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Color iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: kTextPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: kTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatsRowSkeleton extends StatelessWidget {
  const _StatsRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 108,
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 108,
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screened Call Card
// ─────────────────────────────────────────────────────────────────────────────

class _ScreenedCallCard extends StatelessWidget {
  final UnifiedCallEntry entry;
  const _ScreenedCallCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cat = entry.category ?? 'UNKNOWN';
    final catColor = kCategoryColors[cat] ?? Colors.grey;
    final catEmoji = kCategoryEmojis[cat] ?? '❓';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(catEmoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: catColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: catColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Time
          Text(
            DateFormat('h:mm a').format(entry.time),
            style:
                const TextStyle(fontSize: 11, color: kTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_missed_rounded,
                size: 30, color: kPurpleDark),
          ),
          const SizedBox(height: 16),
          const Text(
            'No screened calls yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Zentra will show AI-screened calls here.',
            style: TextStyle(fontSize: 12, color: kTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'Home Screen')
Widget previewHomeScreen() {
  return const ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    ),
  );
}