import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../models/unified_call_entry.dart';
import '../services/api_service.dart';

final unifiedCallHistoryProvider =
    FutureProvider<List<UnifiedCallEntry>>((ref) async {
  final storage = const FlutterSecureStorage();
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
  } catch (_) {
    // Permission not granted or not available
  }

  // Source 2: Backend (AI-screened calls)
  final backendEntries = <UnifiedCallEntry>[];
  if (userId.isNotEmpty) {
    try {
      backendEntries.addAll(await api.getCallHistory(userId));
    } catch (_) {}
  }

  // Merge and sort by time descending
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
      appBar: AppBar(
        title: const Text('Call History', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(unifiedCallHistoryProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(unifiedCallHistoryProvider),
        child: history.when(
          data: (calls) => calls.isEmpty
              ? const _EmptyHistory()
              : ListView.builder(
                  itemCount: calls.length,
                  itemBuilder: (ctx, i) {
                    final entry = calls[i];
                    if (entry.wasAIScreened) {
                      return _AIScreenedCallTile(entry: entry);
                    } else {
                      return _NormalCallTile(entry: entry);
                    }
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error loading history: $err')),
        ),
      ),
    );
  }
}

class _NormalCallTile extends StatelessWidget {
  final UnifiedCallEntry entry;
  const _NormalCallTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final callType = entry.callType ?? 'UNKNOWN';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _callTypeColor(callType).withOpacity(0.15),
        child: Icon(_callTypeIcon(callType), color: _callTypeColor(callType), size: 20),
      ),
      title: Text(
        entry.contactName?.isNotEmpty == true ? entry.contactName! : entry.number,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          Text(
            DateFormat('MMM d, h:mm a').format(entry.time),
            style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
          ),
          if (entry.durationSeconds != null && entry.durationSeconds! > 0) ...[
            const SizedBox(width: 8),
            Text(
              entry.formattedDuration,
              style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.call_outlined, color: Colors.green),
        onPressed: () async {
          final uri = Uri(scheme: 'tel', path: entry.number);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }

  IconData _callTypeIcon(String type) {
    switch (type) {
      case 'INCOMING':
        return Icons.call_received;
      case 'OUTGOING':
        return Icons.call_made;
      case 'MISSED':
        return Icons.call_missed;
      case 'REJECTED':
        return Icons.call_end;
      default:
        return Icons.phone;
    }
  }

  Color _callTypeColor(String type) {
    switch (type) {
      case 'INCOMING':
        return Colors.blue;
      case 'OUTGOING':
        return Colors.green;
      case 'MISSED':
        return Colors.red;
      case 'REJECTED':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

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
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final cat = widget.entry.category ?? 'UNKNOWN';
    final catColor = kCategoryColors[cat] ?? Colors.grey;
    final catEmoji = kCategoryEmojis[cat] ?? '❓';
    final urgency = widget.entry.urgencyScore;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(catEmoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                const SizedBox(width: 8),
                if (urgency != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _urgencyColor(urgency).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'U:$urgency',
                      style: TextStyle(
                        color: _urgencyColor(urgency),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Row(
              children: [
                Text(
                  widget.entry.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM d, h:mm a').format(widget.entry.time),
                  style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
                ),
              ],
            ),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),

          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),

                  // Full transcript
                  if (widget.entry.transcript != null &&
                      widget.entry.transcript!.isNotEmpty) ...[
                    Text(
                      'Transcript',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.entry.transcript!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // AI summary
                  if (widget.entry.aiSummary != null &&
                      widget.entry.aiSummary!.isNotEmpty) ...[
                    Text(
                      'AI Summary',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.entry.aiSummary!,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Call back
                      OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri(scheme: 'tel', path: widget.entry.fullNumber);
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.call_outlined, size: 16),
                        label: const Text('Call Back'),
                      ),

                      // View FIR (scam only)
                      if (cat == 'SCAM' && widget.entry.firPdfUrl != null)
                        FilledButton.icon(
                          onPressed: () async {
                            await launchUrl(
                              Uri.parse(widget.entry.firPdfUrl!),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.description_outlined, size: 16),
                          label: const Text('View FIR'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),

                      // Verify blockchain (scam only)
                      if (cat == 'SCAM' && widget.entry.blockchainTxHash != null)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final url =
                                'https://amoy.polygonscan.com/tx/${widget.entry.blockchainTxHash}';
                            await launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Verify on Chain'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _urgencyColor(int score) {
    if (score >= 8) return Colors.red;
    if (score >= 5) return Colors.orange;
    return Colors.green;
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
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No calls yet',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }
}