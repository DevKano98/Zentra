import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/unified_call_entry.dart';
import '../services/api_service.dart';

final recentDialerCallsProvider =
    FutureProvider<List<UnifiedCallEntry>>((ref) async {
  return ApiService().getRecentCalls(limit: 5);
});

class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key});

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends ConsumerState<DialerScreen> {
  String _dialedNumber = '';

  void _appendDigit(String digit) {
    setState(() => _dialedNumber += digit);
  }

  void _backspace() {
    if (_dialedNumber.isNotEmpty) {
      setState(() =>
          _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1));
    }
  }

  static const _callControlChannel = MethodChannel('com.zentra.dialer/call_control');

  Future<void> _placeCall() async {
    if (_dialedNumber.isEmpty) return;
    try {
      await _callControlChannel.invokeMethod('placeCall', {'number': _dialedNumber});
    } catch (e) {
      debugPrint('Failed to place call: $e');
    }
  }

  Future<void> _callNumber(String number) async {
    try {
      await _callControlChannel.invokeMethod('placeCall', {'number': number});
    } catch (e) {
      debugPrint('Failed to call number: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final recentCalls = ref.watch(recentDialerCallsProvider);

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Dialer', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Number display field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dialedNumber.isEmpty
                        ? 'Enter number'
                        : _formatDisplay(_dialedNumber),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: _dialedNumber.isEmpty
                          ? color.onSurface.withOpacity(0.4)
                          : color.onSurface,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_dialedNumber.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: _backspace,
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Number pad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            child: Column(
              children: [
                _buildRow(['1', '2', '3']),
                _buildRow(['4', '5', '6']),
                _buildRow(['7', '8', '9']),
                _buildRow(['*', '0', '#']),
              ],
            ),
          ),

          // Call button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _dialedNumber.isNotEmpty ? _placeCall : null,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _dialedNumber.isNotEmpty
                      ? Colors.green
                      : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  boxShadow: _dialedNumber.isNotEmpty
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 32),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Recent AI-screened calls
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Recent Screened Calls',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: recentCalls.when(
                    data: (calls) => ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: calls.length,
                      itemBuilder: (ctx, i) {
                        final entry = calls[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.primaryContainer,
                            child: Text(
                              entry.displayName.isNotEmpty
                                  ? entry.displayName[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(entry.displayName),
                          subtitle: Text(entry.category ?? 'Screened'),
                          trailing: IconButton(
                            icon: const Icon(Icons.call_outlined,
                                color: Colors.green),
                            onPressed: () => _callNumber(entry.fullNumber),
                          ),
                        );
                      },
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> digits) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:
            digits.map((d) => _DialKey(label: d, onTap: _appendDigit)).toList(),
      ),
    );
  }

  String _formatDisplay(String number) {
    // Simple formatting: add spaces every 3-4 digits
    if (number.length <= 5) return number;
    if (number.length <= 10 && number.length > 7) {
      return '${number.substring(0, number.length - 7)} ${number.substring(number.length - 7, number.length - 4)} ${number.substring(number.length - 4)}';
    } else if (number.length > 5 && number.length <= 7) {
      return '${number.substring(0, number.length - 4)} ${number.substring(number.length - 4)}';
    }
    return number;
  }
}

class _DialKey extends StatelessWidget {
  final String label;
  final void Function(String) onTap;

  const _DialKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(label),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'Dialer Screen')
Widget previewDialerScreen() {
  return const ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DialerScreen(),
    ),
  );
}
