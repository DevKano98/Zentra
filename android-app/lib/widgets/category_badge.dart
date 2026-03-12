import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../core/constants.dart';

/// Displays a coloured pill badge for a call category.
/// Accepts any string from [kCategoryColors] keys:
/// SCAM | SPAM | TELEMARKETING | OTP | DELIVERY | UNKNOWN | LEGITIMATE
class CategoryBadge extends StatelessWidget {
  final String category;

  /// Controls overall size. Default is [BadgeSize.small].
  final BadgeSize size;

  /// Show the emoji prefix alongside the label.
  final bool showEmoji;

  const CategoryBadge({
    super.key,
    required this.category,
    this.size = BadgeSize.small,
    this.showEmoji = false,
  });

  @override
  Widget build(BuildContext context) {
    final cat = category.toUpperCase();
    final bgColor = (kCategoryColors[cat] ?? Colors.grey).withOpacity(0.14);
    final textColor = kCategoryColors[cat] ?? Colors.grey;
    final emoji = kCategoryEmojis[cat] ?? '';

    final label = showEmoji && emoji.isNotEmpty ? '$emoji $cat' : cat;

    final (fontSize, hPad, vPad, radius) = switch (size) {
      BadgeSize.small => (10.0, 8.0, 3.0, 20.0),
      BadgeSize.medium => (12.0, 12.0, 5.0, 24.0),
      BadgeSize.large => (14.0, 16.0, 6.0, 30.0),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: textColor.withOpacity(0.15), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

enum BadgeSize { small, medium, large }

/// Horizontal scrollable row of multiple [CategoryBadge] widgets.
/// Useful for filter rows.
class CategoryFilterRow extends StatefulWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const CategoryFilterRow({
    super.key,
    required this.categories,
    required this.onChanged,
    this.selected,
  });

  @override
  State<CategoryFilterRow> createState() => _CategoryFilterRowState();
}

class _CategoryFilterRowState extends State<CategoryFilterRow> {
  String? _active;

  @override
  void initState() {
    super.initState();
    _active = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // "All" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: _active == null,
              onSelected: (_) {
                setState(() => _active = null);
                widget.onChanged(null);
              },
            ),
          ),
          // Per-category chips
          ...widget.categories.map((cat) {
            final catUpper = cat.toUpperCase();
            final catColor = kCategoryColors[catUpper] ?? Colors.grey;
            final emoji = kCategoryEmojis[catUpper] ?? '';
            final isSelected = _active == catUpper;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('$emoji $catUpper',
                    style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? catColor : null,
                        fontWeight: isSelected ? FontWeight.bold : null)),
                selected: isSelected,
                selectedColor: catColor.withOpacity(0.15),
                checkmarkColor: catColor,
                side: BorderSide(
                  color: isSelected ? catColor : theme.colorScheme.outlineVariant,
                ),
                onSelected: (_) {
                  setState(() => _active = isSelected ? null : catUpper);
                  widget.onChanged(isSelected ? null : catUpper);
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

@Preview(name: 'Category Badge Previews')
Widget previewCategoryBadge() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CategoryBadge(category: 'SCAM', size: BadgeSize.large, showEmoji: true),
            const SizedBox(height: 16),
            const CategoryBadge(category: 'LEGITIMATE', size: BadgeSize.medium),
            const SizedBox(height: 16),
            CategoryFilterRow(categories: const ['SCAM', 'OTP', 'DELIVERY'], onChanged: (val) {}),
          ],
        ),
      ),
    ),
  );
}