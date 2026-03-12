import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/voice_settings_widget.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _api = ApiService();

  double _urgencyThreshold = kDefaultUrgencyThreshold.toDouble();
  String _voiceLanguage = 'Hindi';
  String _voiceGender = 'Female';
  String _backendUrl = kDefaultBackendUrl;
  String _telegramChatId = '';
  bool _saving = false;
  bool _loaded = false;

  final _backendUrlCtrl = TextEditingController();
  final _telegramCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    _telegramCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final threshold = await _storage.read(key: kStorageUrgencyThreshold);
    final lang = await _storage.read(key: kStorageVoiceLanguage);
    final gender = await _storage.read(key: kStorageVoiceGender);
    final url = await _storage.read(key: kStorageBackendUrl);
    final telegram = await _storage.read(key: kStorageTelegramChatId);

    setState(() {
      _urgencyThreshold =
          double.tryParse(threshold ?? '') ?? kDefaultUrgencyThreshold.toDouble();
      _voiceLanguage = lang ?? 'Hindi';
      _voiceGender = gender ?? 'Female';
      _backendUrl = url ?? kDefaultBackendUrl;
      _telegramChatId = telegram ?? '';
      _backendUrlCtrl.text = _backendUrl;
      _telegramCtrl.text = _telegramChatId;
      _loaded = true;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await _storage.write(
          key: kStorageUrgencyThreshold,
          value: _urgencyThreshold.round().toString());
      await _storage.write(key: kStorageVoiceLanguage, value: _voiceLanguage);
      await _storage.write(key: kStorageVoiceGender, value: _voiceGender);
      await _storage.write(
          key: kStorageBackendUrl, value: _backendUrlCtrl.text.trim());
      await _storage.write(
          key: kStorageTelegramChatId, value: _telegramCtrl.text.trim());

      final userId = await _storage.read(key: kStorageUserId) ?? '';
      if (userId.isNotEmpty) {
        await _api.updatePreferences(
          userId: userId,
          urgencyThreshold: _urgencyThreshold.round(),
          voiceLanguage: _voiceLanguage,
          voiceGender: _voiceGender,
          telegramChatId: _telegramCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveSettings,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice Settings
          _SectionHeader(title: 'Voice Settings'),
          VoiceSettingsWidget(
            language: _voiceLanguage,
            gender: _voiceGender,
            onChanged: (settings) {
              setState(() {
                _voiceLanguage = settings['language']!;
                _voiceGender = settings['gender']!;
              });
            },
          ),

          const SizedBox(height: 24),

          // Urgency Threshold
          _SectionHeader(title: 'Urgency Threshold'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Alert me when urgency is at least:'),
                    Text(
                      _urgencyThreshold.round().toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color.primary,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _urgencyThreshold,
                  min: kUrgencyMin.toDouble(),
                  max: kUrgencyMax.toDouble(),
                  divisions: 9,
                  onChanged: (v) => setState(() => _urgencyThreshold = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // OTP Guard (always on)
          _SectionHeader(title: 'OTP Guard'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, color: color.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('OTP Guard',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'ALWAYS ON',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AI automatically blocks calls trying to extract OTPs. This cannot be disabled for your security.',
                        style: TextStyle(
                          fontSize: 12,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Telegram
          _SectionHeader(title: 'Telegram Alerts'),
          TextField(
            controller: _telegramCtrl,
            decoration: const InputDecoration(
              labelText: 'Telegram Chat ID',
              hintText: 'e.g. 123456789',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.telegram),
            ),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 24),

          // Advanced: Backend URL
          _SectionHeader(title: 'Advanced'),
          TextField(
            controller: _backendUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://zentra-backend.onrender.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud_outlined),
            ),
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}