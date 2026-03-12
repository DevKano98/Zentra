import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../models/call_record.dart';
import 'category_badge.dart';

/// A unified card for displaying a [CallRecord].
/// Supports collapsed and expanded states.
/// Expanded state shows transcript, AI summary, and action buttons.
class CallCard extends StatefulWidget {
  final CallRecord record;

  /// If true, always shows in expanded mode (no toggle).
  final bool alwaysExpanded;

  /// Called when "View FIR" is tapped.
  final VoidCallback? onViewFir;

  /// Called when "Verify on Chain" is tapped.
  final VoidCallback? onVerifyChain;

  const CallCard({
    super.key,
    required this.record,
    this.alwaysExpanded = false,
    this.onViewFir,
    this.onVerifyChain,
  });

  @override
  State<CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<CallCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.alwaysExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.alwaysExpanded) return;
    setState(() => _expanded = !_expanded);
    _expanded ? _controller.forward() : _controller.reverse();
  }

  Future<void> _callBack() async {
    final uri = Uri(scheme: 'tel', path: widget.record.number);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final r = widget.record;
    final cat = r.categoryLabel;
    final catColor = kCategoryColors[cat] ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _expanded ? catColor.withOpacity(0.4) : color.outlineVariant,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.alwaysExpanded ? null : _toggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(record: r, expanded: _expanded, onToggle: _toggle,
                  alwaysExpanded: widget.alwaysExpanded),
              SizeTransition(
                sizeFactor: _expandAnim,
                child: _ExpandedBody(
                  record: r,
                  onCallBack: _callBack,
                  onViewFir: widget.onViewFir,
                  onVerifyChain: widget.onVerifyChain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CallRecord record;
  final bool expanded;
  final bool alwaysExpanded;
  final VoidCallback onToggle;

  const _Header({
    required this.record,
    required this.expanded,
    required this.alwaysExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final cat = record.categoryLabel;
    final catEmoji = kCategoryEmojis[cat] ?? '❓';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Emoji avatar
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: (kCategoryColors[cat] ?? Colors.grey).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(catEmoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(width: 12),

        // Info column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryBadge(category: cat),
                  if (record.urgencyScore != null) ...[
                    const SizedBox(width: 6),
                    _UrgencyPill(score: record.urgencyScore!),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                record.displayName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                _formatMeta(record),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: color.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),

        // Expand chevron
        if (!alwaysExpanded)
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.keyboard_arrow_down,
                color: color.onSurfaceVariant, size: 20),
          ),
      ],
    );
  }

  String _formatMeta(CallRecord r) {
    final parts = <String>[];
    parts.add(DateFormat('MMM d, h:mm a').format(r.startedAt));
    if (r.formattedDuration.isNotEmpty) parts.add(r.formattedDuration);
    return parts.join(' · ');
  }
}

class _ExpandedBody extends StatelessWidget {
  final CallRecord record;
  final VoidCallback onCallBack;
  final VoidCallback? onViewFir;
  final VoidCallback? onVerifyChain;

  const _ExpandedBody({
    required this.record,
    required this.onCallBack,
    this.onViewFir,
    this.onVerifyChain,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),

        // Transcript
        if (record.transcript != null && record.transcript!.isNotEmpty) ...[
          _SectionLabel(label: 'Transcript'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.surfaceVariant.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              record.transcript!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(height: 1.5, color: color.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // AI Summary
        if (record.aiSummary != null && record.aiSummary!.isNotEmpty) ...[
          _SectionLabel(label: 'AI Summary'),
          const SizedBox(height: 6),
          Text(
            record.aiSummary!,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
        ],

        // Action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              icon: Icons.call_outlined,
              label: 'Call Back',
              onTap: onCallBack,
            ),
            if (record.isScam && record.hasFir)
              _ActionButton(
                icon: Icons.description_outlined,
                label: 'View FIR',
                filled: true,
                fillColor: Colors.red,
                onTap: onViewFir,
              ),
            if (record.isScam && record.hasBlockchain)
              _ActionButton(
                icon: Icons.link,
                label: 'Verify on Chain',
                onTap: onVerifyChain,
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  final int score;
  const _UrgencyPill({required this.score});

  Color get _color {
    if (score >= 8) return Colors.red;
    if (score >= 5) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'U$score',
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final Color? fillColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.fillColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
          backgroundColor: fillColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}