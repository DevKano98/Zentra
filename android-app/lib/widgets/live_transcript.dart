import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../core/call_manager.dart';
import '../core/constants.dart';

/// Displays the real-time AI call transcript sourced from [callManagerProvider].
///
/// Renders differently depending on call state:
///   - IDLE        → nothing (empty SizedBox)
///   - INCOMING    → "Connecting…" shimmer
///   - ACTIVE      → scrolling live text + waveform indicator
///   - CLASSIFYING → "Analysing…" spinner
class LiveTranscript extends ConsumerWidget {
  /// Fixed height for the transcript scroll area. Defaults to 120.
  final double transcriptHeight;

  /// If true, renders a minimal single-line chip instead of a full card.
  final bool compact;

  const LiveTranscript({
    super.key,
    this.transcriptHeight = 120,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callManagerProvider);

    if (callState.state == CallState.idle) return const SizedBox.shrink();

    if (compact) return _CompactChip(callState: callState);

    return _FullCard(
      callState: callState,
      transcriptHeight: transcriptHeight,
    );
  }
}

// ── Full card ─────────────────────────────────────────────────────────────────

class _FullCard extends StatefulWidget {
  final CallManagerState callState;
  final double transcriptHeight;

  const _FullCard({required this.callState, required this.transcriptHeight});

  @override
  State<_FullCard> createState() => _FullCardState();
}

class _FullCardState extends State<_FullCard> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_FullCard old) {
    super.didUpdateWidget(old);
    // Auto-scroll to bottom whenever transcript grows
    if (widget.callState.liveTranscript != old.callState.liveTranscript) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final s = widget.callState;
    final number = s.activeSession?.number ?? '';
    final maskedNumber = number.length > 4
        ? '••••${number.substring(number.length - 4)}'
        : number;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: color.primaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.primary.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                _StateIndicator(state: s.state),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _headerLabel(s.state),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (maskedNumber.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      maskedNumber,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Transcript / status body
            SizedBox(
              height: widget.transcriptHeight,
              child: _buildBody(context, s),
            ),

            // Category + urgency strip (shown once available)
            if (s.activeSession?.category != null) ...[
              const Divider(height: 16),
              _CategoryStrip(session: s.activeSession!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, CallManagerState s) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    switch (s.state) {
      case CallState.incoming:
        return const Center(
          child: SpinKitThreeBounce(color: Color(0xFF4F46E5), size: 24),
        );

      case CallState.classifying:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpinKitFadingCircle(
                color: color.primary,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                'Analysing call…',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: color.onSurfaceVariant),
              ),
            ],
          ),
        );

      case CallState.active:
        final text = s.liveTranscript;
        return text.isEmpty
            ? Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SpinKitWave(color: color.primary, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Listening…',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: color.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                controller: _scroll,
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              );

      default:
        return const SizedBox.shrink();
    }
  }

  String _headerLabel(CallState state) {
    switch (state) {
      case CallState.incoming:
        return 'Incoming call detected';
      case CallState.active:
        return 'Live Transcript';
      case CallState.classifying:
        return 'Classifying call…';
      default:
        return '';
    }
  }
}

// ── Compact chip ──────────────────────────────────────────────────────────────

class _CompactChip extends StatelessWidget {
  final CallManagerState callState;
  const _CompactChip({required this.callState});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateIndicator(state: callState.state),
          const SizedBox(width: 6),
          Text(
            callState.liveTranscript.isNotEmpty
                ? _truncate(callState.liveTranscript, 40)
                : _headerLabel(callState.state),
            style: TextStyle(
              fontSize: 12,
              color: color.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return '…${text.substring(text.length - max)}';
  }

  String _headerLabel(CallState state) {
    switch (state) {
      case CallState.incoming:
        return 'Incoming…';
      case CallState.active:
        return 'Screening…';
      case CallState.classifying:
        return 'Classifying…';
      default:
        return '';
    }
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _StateIndicator extends StatelessWidget {
  final CallState state;
  const _StateIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == CallState.active) {
      return SpinKitWave(
        color: Theme.of(context).colorScheme.primary,
        size: 14,
        itemCount: 4,
      );
    }
    return SpinKitPulse(
      color: Theme.of(context).colorScheme.primary,
      size: 14,
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  final CallSession session;
  const _CategoryStrip({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = session.category?.toUpperCase() ?? 'UNKNOWN';
    final catColor = kCategoryColors[cat] ?? Colors.grey;
    final emoji = kCategoryEmojis[cat] ?? '❓';
    final urgency = session.urgencyScore;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: catColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: catColor.withOpacity(0.3)),
          ),
          child: Text(
            '$emoji $cat',
            style: TextStyle(
              color: catColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (urgency != null) ...[
          const SizedBox(width: 8),
          Text(
            'Urgency: $urgency/10',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _urgencyColor(urgency),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Color _urgencyColor(int score) {
    if (score >= 8) return Colors.red;
    if (score >= 5) return Colors.orange;
    return Colors.green;
  }
}