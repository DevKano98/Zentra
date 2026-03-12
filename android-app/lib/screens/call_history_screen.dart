import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/unified_call_entry.dart';
import '../services/api_service.dart';

const _callControlChannel = MethodChannel('com.zentra.dialer/call_control');

final unifiedCallHistoryProvider =
    FutureProvider<List<UnifiedCallEntry>>((ref) async {
  const storage = FlutterSecureStorage();
  final userId = await storage.read(key: kStorageUserId) ?? '';
  final api = ApiService();

  // Source 1: Device call log
  final deviceEntries = <UnifiedCallEntry>[];
  try {
    final entries = await CallLog.get();
    for (final entry in entries) {
      deviceEntries.add(UnifiedCallEntry(
        contactName: entry.name,
        number: entry.number ?? '',
        time: DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0),
        durationSeconds: entry.duration,
        wasAIScreened: false,
        callType: _mapCallType(entry.callType),
      ));
    }
  } catch (_) {}

  // Source 2: Backend (AI-screened calls)
  final backendEntries = <UnifiedCallEntry>[];
  if (userId.isNotEmpty) {
    try {
      backendEntries.addAll(await api.getCallHistory(userId));
    } catch (_) {}
  }

  // Merge and sort
  final all = [...deviceEntries, ...backendEntries];
  all.sort((a, b) => b.time.compareTo(a.time));
  return all;
});

String _mapCallType(CallType? type) {
  switch (type) {
    case CallType.incoming:
      return 'INCOMING';
    case CallType.outgoing:
      return 'OUTGOING';
    case CallType.missed:
      return 'MISSED';
    case CallType.rejected:
      return 'REJECTED';
    default:
      return 'UNKNOWN';
  }
}

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(unifiedCallHistoryProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Call History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(unifiedCallHistoryProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: kPurpleDeep,
        onRefresh: () async => ref.invalidate(unifiedCallHistoryProvider),
        child: history.when(
          data: (calls) => calls.isEmpty
              ? const _EmptyHistory()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: calls.length,
                  itemBuilder: (ctx, i) {
                    final entry = calls[i];
                    return entry.wasAIScreened
                        ? _AIScreenedCallTile(entry: entry)
                        : _NormalCallTile(entry: entry);
                  },
                ),
          loading: () => const Center(
            child: CircularProgressIndicator(
              color: kPurpleDark, strokeWidth: 2),
          ),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading history: $err',
                  style: const TextStyle(color: kTextSecondary)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Normal (device) call tile
// ─────────────────────────────────────────────────────────────────────────────

class _NormalCallTile extends StatelessWidget {
  final UnifiedCallEntry entry;
  const _NormalCallTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final callType = entry.callType ?? 'UNKNOWN';
    final typeColor = _callTypeColor(callType);
    final typeIcon = _callTypeIcon(callType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: ListTile(
        onTap: () => _showBottomActions(context, entry),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(typeIcon, color: typeColor, size: 20),
        ),
        title: Text(
          entry.contactName?.isNotEmpty == true
              ? entry.contactName!
              : entry.number,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary),
        ),
        subtitle: Row(
          children: [
            Text(
              DateFormat('MMM d, h:mm a').format(entry.time),
              style: const TextStyle(fontSize: 11, color: kTextSecondary),
            ),
            if (entry.durationSeconds != null &&
                entry.durationSeconds! > 0) ...[
              const Text('  ·  ',
                  style: TextStyle(color: kTextSecondary, fontSize: 11)),
              Text(
                entry.formattedDuration,
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
              ),
            ],
          ],
        ),
        trailing: GestureDetector(
          onTap: () async {
            final number = entry.number;
            try {
              await _callControlChannel.invokeMethod('placeCall', {'number': number});
            } catch (e) {
              final uri = Uri(scheme: 'tel', path: number);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_rounded,
                color: kPurpleDeep, size: 16),
          ),
        ),
      ),
    );
  }

  void _showBottomActions(BuildContext context, UnifiedCallEntry entry) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.call_rounded, color: Colors.green),
                title: const Text('Call'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final number = entry.number;
                  try {
                    await _callControlChannel.invokeMethod('placeCall', {'number': number});
                  } catch (e) {
                    final uri = Uri(scheme: 'tel', path: number);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.message_rounded, color: Colors.blue),
                title: const Text('Send Message'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri(scheme: 'sms', path: entry.number);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy Number'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: entry.number));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Number copied')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Colors.red),
                title: const Text('Block Number'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _callControlChannel.invokeMethod('blockNumber', {'number': entry.number});
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Number blocked')));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to block: $e')));
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete from History'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _callControlChannel.invokeMethod('deleteCallLog', {'number': entry.number});
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Deleted from history')));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  IconData _callTypeIcon(String type) {
    switch (type) {
      case 'INCOMING':
        return Icons.call_received_rounded;
      case 'OUTGOING':
        return Icons.call_made_rounded;
      case 'MISSED':
        return Icons.call_missed_rounded;
      case 'REJECTED':
        return Icons.call_end_rounded;
      default:
        return Icons.phone_rounded;
    }
  }

  Color _callTypeColor(String type) {
    switch (type) {
      case 'INCOMING':
        return const Color(0xFF2563EB);
      case 'OUTGOING':
        return const Color(0xFF16A34A);
      case 'MISSED':
        return const Color(0xFFDC2626);
      case 'REJECTED':
        return const Color(0xFFEA580C);
      default:
        return kTextSecondary;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI-screened call tile (expandable)
// ─────────────────────────────────────────────────────────────────────────────

class _AIScreenedCallTile extends StatefulWidget {
  final UnifiedCallEntry entry;
  const _AIScreenedCallTile({required this.entry});

  @override
  State<_AIScreenedCallTile> createState() => _AIScreenedCallTileState();
}

class _AIScreenedCallTileState extends State<_AIScreenedCallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cat = widget.entry.category ?? 'UNKNOWN';
    final catColor = kCategoryColors[cat] ?? Colors.grey;
    final catEmoji = kCategoryEmojis[cat] ?? '❓';
    final urgency = widget.entry.urgencyScore;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded ? catColor.withOpacity(0.5) : kBorder,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Emoji avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(catEmoji,
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges row
                        Row(
                          children: [
                            _CategoryPill(cat: cat, color: catColor),
                            if (urgency != null) ...[
                              const SizedBox(width: 6),
                              _UrgencyPill(score: urgency),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.entry.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary,
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, h:mm a').format(widget.entry.time),
                          style: const TextStyle(
                              fontSize: 11, color: kTextSecondary),
                        ),
                      ],
                    ),
                  ),

                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: kTextSecondary, size: 20),
                  ),
                ],
              ),
            ),
          ),

          // Expanded body
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _ExpandedContent(entry: widget.entry, cat: cat),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  final UnifiedCallEntry entry;
  final String cat;
  const _ExpandedContent({required this.entry, required this.cat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Transcript
          if (entry.transcript != null && entry.transcript!.isNotEmpty) ...[
            const _SectionLabel(label: 'TRANSCRIPT'),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPurple.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                entry.transcript!,
                style: const TextStyle(
                    fontSize: 13, color: kTextPrimary, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // AI Summary
          if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) ...[
            const _SectionLabel(label: 'AI SUMMARY'),
            const SizedBox(height: 6),
            Text(
              entry.aiSummary!,
              style: const TextStyle(
                  fontSize: 13, color: kTextPrimary, height: 1.5),
            ),
            const SizedBox(height: 12),
          ],

          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionBtn(
                icon: Icons.call_rounded,
                label: 'Call Back',
                onTap: () async {
                  final number = entry.fullNumber;
                  try {
                    await _callControlChannel.invokeMethod('placeCall', {'number': number});
                  } catch (e) {
                    final uri = Uri(scheme: 'tel', path: number);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              if (cat == 'SCAM' && entry.firPdfUrl != null)
                _ActionBtn(
                  icon: Icons.description_outlined,
                  label: 'View FIR',
                  danger: true,
                  onTap: () async {
                    await launchUrl(
                      Uri.parse(entry.firPdfUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              if (cat == 'SCAM' && entry.blockchainTxHash != null)
                _ActionBtn(
                  icon: Icons.link_rounded,
                  label: 'Verify on Chain',
                  onTap: () async {
                    final url =
                        'https://amoy.polygonscan.com/tx/${entry.blockchainTxHash}';
                    await launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryPill extends StatelessWidget {
  final String cat;
  final Color color;
  const _CategoryPill({required this.cat, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        cat,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  final int score;
  const _UrgencyPill({required this.score});

  Color get _color {
    if (score >= 8) return const Color(0xFFDC2626);
    if (score >= 5) return const Color(0xFFEA580C);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'U$score',
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: kPurpleDark,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (danger) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded,
                size: 38, color: kPurpleDark),
          ),
          const SizedBox(height: 20),
          const Text(
            'No calls yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your call history will appear here.',
            style: TextStyle(fontSize: 13, color: kTextSecondary),
          ),
        ],
      ),
    );
  }
}