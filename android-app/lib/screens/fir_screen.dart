import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../models/unified_call_entry.dart';
import '../services/api_service.dart';

final scamCallsProvider = FutureProvider<List<UnifiedCallEntry>>((ref) async {
  final storage = const FlutterSecureStorage();
  final userId = await storage.read(key: kStorageUserId) ?? '';
  if (userId.isEmpty) return [];
  final all = await ApiService().getCallHistory(userId);
  return all.where((e) => e.category == 'SCAM').toList();
});

class FirScreen extends ConsumerWidget {
  const FirScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scamCalls = ref.watch(scamCallsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FIR Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(scamCallsProvider),
          ),
        ],
      ),
      body: scamCalls.when(
        data: (calls) => calls.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        size: 64, color: Colors.green.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No scam calls recorded',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Stay safe — Zentra is watching.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: calls.length,
                itemBuilder: (ctx, i) => _FirCard(entry: calls[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _FirCard extends StatelessWidget {
  final UnifiedCallEntry entry;
  const _FirCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'SCAM',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, yyyy').format(entry.time),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  entry.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),

            if (entry.urgencyScore != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.speed, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Urgency: ${entry.urgencyScore}/10',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],

            if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.aiSummary!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                if (entry.firPdfUrl != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _downloadFir(context, entry),
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('View FIR'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_empty, size: 16),
                      label: const Text('FIR Pending'),
                    ),
                  ),

                if (entry.blockchainTxHash != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _verifyOnChain(entry.blockchainTxHash!),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Verify'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFir(BuildContext context, UnifiedCallEntry entry) async {
    try {
      // Get signed URL from backend
      final signedUrl = await ApiService().downloadReport(entry.firPdfUrl!);
      await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error downloading FIR: $e')));
      }
    }
  }

  Future<void> _verifyOnChain(String txHash) async {
    final url = 'https://amoy.polygonscan.com/tx/$txHash';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}