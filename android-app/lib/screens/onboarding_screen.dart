import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/voice_settings_widget.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _setupChannel = MethodChannel(kChannelSetup);
  final _storage = const FlutterSecureStorage();
  final _api = ApiService();

  int _step = 0;

  // Step 1
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  // Step 2
  double _urgencyThreshold = kDefaultUrgencyThreshold.toDouble();

  // Step 3
  String _voiceLanguage = 'Hindi';
  String _voiceGender = 'Female';

  // Step 4 permissions
  final Map<String, bool> _permissions = {
    'Phone': false,
    'Contacts': false,
    'Microphone': false,
    'Notifications': false,
    'Call Logs': false,
  };

  bool _isDefaultDialer = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestAllPermissions() async {
    final statuses = await [
      Permission.phone,
      Permission.contacts,
      Permission.microphone,
      Permission.notification,
      Permission.phone,
    ].request();

    setState(() {
      _permissions['Phone'] = statuses[Permission.phone]?.isGranted ?? false;
      _permissions['Contacts'] = statuses[Permission.contacts]?.isGranted ?? false;
      _permissions['Microphone'] = statuses[Permission.microphone]?.isGranted ?? false;
      _permissions['Notifications'] = statuses[Permission.notification]?.isGranted ?? false;
      _permissions['Call Logs'] = statuses[Permission.phone]?.isGranted ?? false;
    });
  }

  Future<void> _requestDefaultDialer() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set as Default Dialer'),
        content: const Text(
          'Zentra needs to be your default phone app to screen incoming calls. '
          'Your contacts and known callers will always ring normally — only unknown numbers will be screened by AI.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _setupChannel.invokeMethod('requestDefaultDialer');
              final isDefault = await _setupChannel.invokeMethod<bool>('isDefaultDialer') ?? false;
              setState(() => _isDefaultDialer = isDefault);
            },
            child: const Text('Set Zentra as Default'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    setState(() => _loading = true);
    try {
      await _storage.write(key: kStorageUserName, value: _nameCtrl.text.trim());
      await _storage.write(key: kStorageUserCity, value: _cityCtrl.text.trim());
      await _storage.write(
          key: kStorageUrgencyThreshold, value: _urgencyThreshold.round().toString());
      await _storage.write(key: kStorageVoiceLanguage, value: _voiceLanguage);
      await _storage.write(key: kStorageVoiceGender, value: _voiceGender);

      await _api.registerUser(
        name: _nameCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        urgencyThreshold: _urgencyThreshold.round(),
        voiceLanguage: _voiceLanguage,
        voiceGender: _voiceGender,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShellRedirect()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    return Scaffold(
      backgroundColor: color.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: List.generate(5, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _step ? color.primary : color.surfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStep(_step),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canProceed() ? _onNext : null,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_step == 4 ? 'Get Started' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    if (_loading) return false;
    switch (_step) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty && _cityCtrl.text.trim().isNotEmpty;
      case 4:
        return _isDefaultDialer;
      default:
        return true;
    }
  }

  void _onNext() {
    if (_step < 4) {
      setState(() => _step++);
    } else {
      _finishOnboarding();
    }
  }

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _buildNameCityStep();
      case 1:
        return _buildUrgencyStep();
      case 2:
        return _buildVoiceStep();
      case 3:
        return _buildPermissionsStep();
      case 4:
        return _buildDefaultDialerStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildNameCityStep() {
    return Padding(
      key: const ValueKey(0),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text('👋', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            "Let's get started",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us a little about yourself so we can personalise your experience.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyStep() {
    return Padding(
      key: const ValueKey(1),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text('⚡', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Urgency Threshold',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'When should Zentra alert you? Set the minimum urgency score for calls to pass through.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 48),
          Center(
            child: Text(
              _urgencyThreshold.round().toString(),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Slider(
            value: _urgencyThreshold,
            min: kUrgencyMin.toDouble(),
            max: kUrgencyMax.toDouble(),
            divisions: 9,
            label: _urgencyThreshold.round().toString(),
            onChanged: (v) => setState(() => _urgencyThreshold = v),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 - Alert for everything', style: TextStyle(fontSize: 12)),
              Text('10 - Only critical calls', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceStep() {
    return Padding(
      key: const ValueKey(2),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text('🗣️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'AI Voice Settings',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the voice and language for your AI call screener.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 40),
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
        ],
      ),
    );
  }

  Widget _buildPermissionsStep() {
    return Padding(
      key: const ValueKey(3),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text('🔐', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Permissions',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Zentra needs these permissions to screen calls and protect you.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ..._permissions.entries.map(
            (e) => _PermissionTile(
              title: e.key,
              granted: e.value,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _requestAllPermissions,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Grant All Permissions'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultDialerStep() {
    return Padding(
      key: const ValueKey(4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text('📱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Set as Default Dialer',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'This is the final step. Zentra must be your default phone app to intercept and screen unknown calls.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF4F46E5)),
                    SizedBox(width: 8),
                    Text('What this means:', fontWeight: FontWeight.bold),
                  ],
                ),
                SizedBox(height: 8),
                Text('• Your contacts always ring normally'),
                Text('• Emergency numbers are never intercepted'),
                Text('• Unknown numbers are screened by AI'),
                Text('• You control who gets through'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (_isDefaultDialer)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Zentra is your default dialer!',
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _requestDefaultDialer,
                icon: const Icon(Icons.phone_android),
                label: const Text('Make Zentra Default Dialer'),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final bool granted;

  const _PermissionTile({required this.title, required this.granted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

// Redirect to main shell after onboarding
class MainShellRedirect extends StatelessWidget {
  const MainShellRedirect({super.key});
  @override
  Widget build(BuildContext context) {
    // Navigate to root which rebuilds with onboarding_complete = true
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (_) => false);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}