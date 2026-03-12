import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';

class VoiceSettingsWidget extends StatefulWidget {
  final String language;
  final String gender;
  final void Function(Map<String, String> settings) onChanged;

  const VoiceSettingsWidget({
    super.key,
    required this.language,
    required this.gender,
    required this.onChanged,
  });

  @override
  State<VoiceSettingsWidget> createState() => _VoiceSettingsWidgetState();
}

class _VoiceSettingsWidgetState extends State<VoiceSettingsWidget> {
  static const _storage = FlutterSecureStorage();

  late String _language;
  late String _gender;

  @override
  void initState() {
    super.initState();
    _language = widget.language;
    _gender = widget.gender;
  }

  Future<void> _updateLanguage(String lang) async {
    setState(() => _language = lang);
    await _storage.write(key: kStorageVoiceLanguage, value: lang);
    widget.onChanged({'language': lang, 'gender': _gender});
  }

  Future<void> _updateGender(String gender) async {
    setState(() => _gender = gender);
    await _storage.write(key: kStorageVoiceGender, value: gender);
    widget.onChanged({'language': _language, 'gender': gender});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language row
          Row(
            children: [
              const Icon(Icons.language, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Language',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: kVoiceLanguages.map((lang) {
              return ChoiceChip(
                label: Text(lang),
                selected: _language == lang,
                onSelected: (selected) {
                  if (selected) _updateLanguage(lang);
                },
                selectedColor: color.primary.withOpacity(0.15),
                showCheckmark: false,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                  color: _language == lang ? color.primary : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color: _language == lang
                      ? color.primary
                      : color.onSurfaceVariant,
                  fontWeight: _language == lang
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Gender row
          Row(
            children: [
              const Icon(Icons.record_voice_over, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Voice',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: kVoiceGenders.map((gender) {
              final icon = gender == 'Female' ? '👩' : '👨';
              return ChoiceChip(
                label: Text('$icon $gender'),
                selected: _gender == gender,
                onSelected: (selected) {
                  if (selected) _updateGender(gender);
                },
                selectedColor: color.primary.withOpacity(0.15),
                showCheckmark: false,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                  color: _gender == gender ? color.primary : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color: _gender == gender
                      ? color.primary
                      : color.onSurfaceVariant,
                  fontWeight: _gender == gender
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}