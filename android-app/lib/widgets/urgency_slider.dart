import 'package:flutter/material.dart';

import '../core/constants.dart';

/// A fully self-contained urgency threshold slider.
///
/// Shows the current value prominently, a slider from 1–10,
/// a colour-coded label (green → orange → red), and hint text
/// explaining what the threshold means in plain language.
class UrgencySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// If true, shows a compact single-row layout (no description text).
  final bool compact;

  const UrgencySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  Color get _trackColor {
    if (value >= 8) return Colors.red;
    if (value >= 5) return Colors.orange;
    return Colors.green;
  }

  String get _levelLabel {
    if (value >= 8) return 'High — only critical calls pass';
    if (value >= 5) return 'Medium — balanced filtering';
    return 'Low — alert on most calls';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) return _buildCompact(theme);
    return _buildFull(theme);
  }

  Widget _buildFull(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Urgency Threshold',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _levelLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: _trackColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _ScoreBubble(score: value.round(), color: _trackColor),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _trackColor,
            thumbColor: _trackColor,
            overlayColor: _trackColor.withOpacity(0.15),
            inactiveTrackColor: _trackColor.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: kUrgencyMin.toDouble(),
            max: kUrgencyMax.toDouble(),
            divisions: kUrgencyMax - kUrgencyMin,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1 · All calls',
                style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
            Text('10 · Critical only',
                style: TextStyle(fontSize: 10, color: Colors.red.shade600)),
          ],
        ),
      ],
    );
  }

  Widget _buildCompact(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _trackColor,
              thumbColor: _trackColor,
              overlayColor: _trackColor.withOpacity(0.15),
              inactiveTrackColor: _trackColor.withOpacity(0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: kUrgencyMin.toDouble(),
              max: kUrgencyMax.toDouble(),
              divisions: kUrgencyMax - kUrgencyMin,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ScoreBubble(score: value.round(), color: _trackColor),
      ],
    );
  }
}

class _ScoreBubble extends StatelessWidget {
  final int score;
  final Color color;

  const _ScoreBubble({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Center(
        child: Text(
          score.toString(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}