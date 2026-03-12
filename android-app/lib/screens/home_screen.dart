import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/call_manager.dart';
import '../models/unified_call_entry.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';

final recentCallsProvider = FutureProvider<List<UnifiedCallEntry>>((ref) async {
  return ApiService().getRecentCalls();
});

final callStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ApiService().getCallStats();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callManagerProvider);
    final recentCalls = ref.watch(recentCallsProvider);
    final stats = ref.watch(callStatsProvider);
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Scaffold(
      backgroundColor: color.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shield, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('Zentra', style: TextStyle(fontWeight: FontWeight.bold)),
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentCallsProvider);
          ref.invalidate(callStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // AI Status Badge
            _AIStatusBadge(callState: callState),

            const SizedBox(height: 16),

            // Live transcript (shown during active call)
            if (callState.state == CallState.active ||
                callState.state == CallState.incoming)
              _LiveTranscriptCard(callState: callState),

            const SizedBox(height: 16),

            // Stats row
            stats.when(
              data: (s) => _StatsRow(callsToday: s['today'] ?? 0, scamsBlocked: s['scams'] ?? 0),
              loading: () => const _StatsRowSkeleton(),
              error: (_, __) => const SizedBox(),
            ),

            const SizedBox(height: 24),

            // Recent AI-screened calls
            Text(
              'Recent Screened Calls',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            recentCalls.when(
              data: (calls) => calls.isEmpty
                  ? _EmptyState()
                  : Column(
                      children: calls
                          .take(3)
                          .map((c) => _ScreenedCallCard(entry: c))
                          .toList(),
                    ),
              loading: () => const Center(
                child: SpinKitThreeBounce(
                  color: Color(0xFF4F46E5),
                  size: 30,
                ),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AIStatusBadge extends StatelessWidget {
  final CallManagerState callState;
  const _AIStatusBadge({required this.callState});

  @override
  Widget build(BuildContext context) {
    final isActive = callState.state != CallState.idle;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]
              : [Colors.grey.shade700, Colors.grey.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isActive
                ? const SpinKitPulse(color: Colors.white, size: 28)
                : const Icon(Icons.shield, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'AI ACTIVE' : 'AI SLEEPING',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  isActive
                      ? _getStatusDescription(callState.state)
                      : 'Monitoring for incoming calls',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isActive ? Colors.greenAccent : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusDescription(CallState state) {
    switch (state) {
      case CallState.incoming:
        return 'Incoming call detected...';
      case CallState.active:
        return 'Screening call in progress';
      case CallState.classifying:
        return 'Classifying call...';
      default:
        return 'Processing';
    }
  }
}

class _LiveTranscriptCard extends StatelessWidget {
  final CallManagerState callState;
  const _LiveTranscriptCard({required this.callState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SpinKitWave(
                color: theme.colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Live Transcript',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                callState.activeSession?.number ?? '',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                callState.liveTranscript.isEmpty
                    ? 'Listening...'
                    : callState.liveTranscript,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
            icon: Icons.phone_outlined,
            color: const Color(0xFF4F46E5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Scams Blocked',
            value: scamsBlocked.toString(),
            icon: Icons.block,
            color: Colors.red,
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
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreenedCallCard extends StatelessWidget {
  final UnifiedCallEntry entry;
  const _ScreenedCallCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = entry.category ?? 'UNKNOWN';
    final catColor = kCategoryColors[cat] ?? Colors.grey;
    final catEmoji = kCategoryEmojis[cat] ?? '❓';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(catEmoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: catColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('h:mm a').format(entry.time),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.displayName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.phone_missed_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No screened calls yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}