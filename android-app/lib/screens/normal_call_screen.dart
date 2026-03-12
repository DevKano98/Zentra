import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/call_manager.dart';

class NormalCallScreen extends ConsumerWidget {
  const NormalCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callManagerProvider);
    final session = callState.activeSession;

    if (session == null || 
       (callState.state != CallState.ringing_normal && 
        callState.state != CallState.active_normal)) {
      return const SizedBox.shrink();
    }

    final isRinging = callState.state == CallState.ringing_normal;
    final isOutgoing = callState.state == CallState.outgoing;
    final number = session.number.isEmpty ? 'Unknown Number' : session.number;

    String statusText = 'Ongoing Call';
    if (isRinging) statusText = 'Incoming Call';
    if (isOutgoing) statusText = 'Outgoing Call...';

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Dark theme for calls
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            
            // Caller Info
            const Icon(Icons.person_pin, size: 80, color: Colors.white54),
            const SizedBox(height: 20),
            Text(
              number,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            
            if (!isRinging) ...[
              const SizedBox(height: 12),
              _CallDurationTicker(startTime: session.startTime),
            ],

            const Spacer(),

            // Actions
            if (isRinging)
              Padding(
                padding: const EdgeInsets.only(bottom: 80, left: 40, right: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CallButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'Decline',
                      onPressed: () => ref.read(callManagerProvider.notifier).declineNormalCall(),
                    ),
                    _CallButton(
                      icon: Icons.call,
                      color: Colors.green,
                      label: 'Answer',
                      onPressed: () => ref.read(callManagerProvider.notifier).answerNormalCall(),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 80, left: 40, right: 40),
                child: Column(
                  children: [
                    if (!isOutgoing) // Hide options during "Connecting" phase
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _CallButton(
                            icon: Icons.mic_off,
                            color: Colors.white24,
                            label: 'Mute',
                            onPressed: () {}, // TODO: Implement mute native call
                          ),
                          _CallButton(
                            icon: Icons.dialpad,
                            color: Colors.white24,
                            label: 'Keypad',
                            onPressed: () {}, 
                          ),
                          _CallButton(
                            icon: Icons.volume_up,
                            color: Colors.white24,
                            label: 'Speaker',
                            onPressed: () {}, 
                          ),
                        ],
                      ),
                    if (!isOutgoing) const SizedBox(height: 40),
                    _CallButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'End',
                      size: 72,
                      iconSize: 36,
                      onPressed: () => ref.read(callManagerProvider.notifier).endCall(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
    this.size = 64,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class _CallDurationTicker extends StatefulWidget {
  final DateTime startTime;
  const _CallDurationTicker({required this.startTime});

  @override
  State<_CallDurationTicker> createState() => _CallDurationTickerState();
}

class _CallDurationTickerState extends State<_CallDurationTicker> {
  late Stream<int> _timer;

  @override
  void initState() {
    super.initState();
    _timer = Stream.periodic(const Duration(seconds: 1), (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _timer,
      builder: (context, _) {
        final duration = DateTime.now().difference(widget.startTime);
        final m = duration.inMinutes.toString().padLeft(2, '0');
        final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
        return Text(
          '$m:$s',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        );
      },
    );
  }
}
