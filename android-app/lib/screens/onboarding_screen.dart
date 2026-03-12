import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/voice_settings_widget.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _channel = MethodChannel('com.zentra.dialer/call_control');
  final _storage = const FlutterSecureStorage();
  final _api = ApiService();

  int _step = 0;

  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  double _urgencyThreshold = kDefaultUrgencyThreshold.toDouble();

  String _voiceLanguage = 'Hindi';
  String _voiceGender = 'Female';

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
    ].request();
    setState(() {
      _permissions['Phone'] = statuses[Permission.phone]?.isGranted ?? false;
      _permissions['Contacts'] =
          statuses[Permission.contacts]?.isGranted ?? false;
      _permissions['Microphone'] =
          statuses[Permission.microphone]?.isGranted ?? false;
      _permissions['Notifications'] =
          statuses[Permission.notification]?.isGranted ?? false;
      _permissions['Call Logs'] =
          statuses[Permission.phone]?.isGranted ?? false;
    });
  }

  Future<void> _setDefaultDialer() async {
    try {
      final result = await _channel.invokeMethod('setDefaultDialer');
      if (result == true) {
        setState(() => _isDefaultDialer = true);
      } else {
        await Future.delayed(const Duration(milliseconds: 1500));
        final check = await _channel.invokeMethod('checkDefaultDialer');
        setState(() => _isDefaultDialer = check == true);
        if (check != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select Zentra as default phone app')),
          );
        }
      }
    } catch (e) {
      await Future.delayed(const Duration(milliseconds: 1500));
      try {
        final check = await _channel.invokeMethod('checkDefaultDialer');
        setState(() => _isDefaultDialer = check == true);
      } catch (_) {}
    }
  }

  Future<void> _requestDefaultDialer() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Set as Default Dialer',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: kTextPrimary)),
        content: const Text(
          'Zentra needs to be your default phone app to screen incoming calls. '
          'Your contacts and known callers will always ring normally — only unknown numbers will be screened by AI.',
          style: TextStyle(color: kTextSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _setDefaultDialer();
            },
            style: FilledButton.styleFrom(
              minimumSize: Size.zero,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Set as Default'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    setState(() => _loading = true);
    try {
      await _storage.write(
          key: kStorageUserName, value: _nameCtrl.text.trim());
      await _storage.write(
          key: kStorageUserCity, value: _cityCtrl.text.trim());
      await _storage.write(
          key: kStorageUrgencyThreshold,
          value: _urgencyThreshold.round().toString());
      await _storage.write(key: kStorageVoiceLanguage, value: _voiceLanguage);
      await _storage.write(key: kStorageVoiceGender, value: _voiceGender);

      final phone = await _storage.read(key: 'phone_number') ?? '';

      await _api.registerUser(
        phoneNumber: phone,
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(5, (i) {
                  final isFilled = i <= _step;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isFilled ? kPurpleDark : kBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Step content ────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: anim, curve: Curves.easeOut)),
                    child: child,
                  ),
                ),
                child: _buildStep(_step),
              ),
            ),

            // ── Bottom nav buttons ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(80, 52),
                      ),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canProceed() ? _onNext : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(140, 52),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kPurpleDeep,
                            ),
                          )
                        : Text(
                            _step == 4 ? '🚀  Get Started' : 'Continue',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
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
        return _nameCtrl.text.trim().isNotEmpty &&
            _cityCtrl.text.trim().isNotEmpty;
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

  // ── Step 0 — Name & City ────────────────────────────────────────────────
  Widget _buildNameCityStep() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _StepIcon(icon: Icons.waving_hand_rounded, color: kPurple),
          const SizedBox(height: 20),
          const Text("Let's get started",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Tell us who you are so we can personalise your experience.',
            style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // ── Step 1 — Urgency ─────────────────────────────────────────────────────
  Widget _buildUrgencyStep() {
    final trackColor = _urgencyThreshold >= 8
        ? const Color(0xFFDC2626)
        : _urgencyThreshold >= 5
            ? const Color(0xFFEA580C)
            : const Color(0xFF16A34A);

    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _StepIcon(icon: Icons.tune_rounded, color: kPurple),
          const SizedBox(height: 20),
          const Text('Urgency Threshold',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Set how urgent a call must be before Zentra alerts you.',
            style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Alert threshold',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary)),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: trackColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: trackColor.withOpacity(0.4), width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          _urgencyThreshold.round().toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: trackColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: trackColor,
                    thumbColor: trackColor,
                    overlayColor: trackColor.withOpacity(0.15),
                    inactiveTrackColor: kBorder,
                  ),
                  child: Slider(
                    value: _urgencyThreshold,
                    min: kUrgencyMin.toDouble(),
                    max: kUrgencyMax.toDouble(),
                    divisions: 9,
                    onChanged: (v) => setState(() => _urgencyThreshold = v),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('1 – All calls',
                        style: TextStyle(fontSize: 11, color: kTextSecondary)),
                    Text('10 – Critical only',
                        style: TextStyle(fontSize: 11, color: kTextSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2 — Voice ───────────────────────────────────────────────────────
  Widget _buildVoiceStep() {
    return SingleChildScrollView(
      key: const ValueKey(2),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _StepIcon(icon: Icons.record_voice_over_rounded, color: kPurple),
          const SizedBox(height: 20),
          const Text('AI Voice Settings',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Choose the voice and language for your AI call screener.',
            style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
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

  // ── Step 3 — Permissions ─────────────────────────────────────────────────
  Widget _buildPermissionsStep() {
    final allGranted = _permissions.values.every((v) => v);
    return SingleChildScrollView(
      key: const ValueKey(3),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _StepIcon(icon: Icons.lock_rounded, color: kPurple),
          const SizedBox(height: 20),
          const Text('Permissions',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Zentra needs these permissions to screen calls and protect you.',
            style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              children: _permissions.entries.map((e) {
                final isLast =
                    e.key == _permissions.keys.last;
                return _PermissionTile(
                  title: e.key,
                  granted: e.value,
                  isLast: isLast,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _requestAllPermissions,
              icon: Icon(
                allGranted
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                color: allGranted ? Colors.green : kPurpleDeep,
              ),
              label: Text(
                allGranted ? 'All Permissions Granted' : 'Grant All Permissions',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 4 — Default dialer ──────────────────────────────────────────────
  Widget _buildDefaultDialerStep() {
    return SingleChildScrollView(
      key: const ValueKey(4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _StepIcon(icon: Icons.phone_android_rounded, color: kPurple),
          const SizedBox(height: 20),
          const Text('Set as Default Dialer',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary)),
          const SizedBox(height: 8),
          const Text(
            'This is the final step. Zentra must be your default phone app to intercept and screen unknown calls.',
            style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),

          // Info card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: kPurple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: kPurpleDeep, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Text('What this means',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 14),
                for (final item in [
                  'Your contacts always ring normally',
                  'Emergency numbers are never intercepted',
                  'Unknown numbers are screened by AI',
                  'You control who gets through',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_rounded,
                            size: 15, color: kPurpleDark),
                        const SizedBox(width: 10),
                        Text(item,
                            style: const TextStyle(
                                fontSize: 13, color: kTextPrimary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_isDefaultDialer)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green),
                  SizedBox(width: 10),
                  Text(
                    'Zentra is your default dialer!',
                    style: TextStyle(
                        color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _requestDefaultDialer,
                icon: const Icon(Icons.phone_android_rounded),
                label: const Text('Make Zentra Default Dialer'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _StepIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: kPurpleDeep, size: 28),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final bool granted;
  final bool isLast;

  const _PermissionTile({
    required this.title,
    required this.granted,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: granted
                      ? const Color(0xFFDCFCE7)
                      : kCardBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: granted ? const Color(0xFF86EFAC) : kBorder,
                  ),
                ),
                child: Icon(
                  granted
                      ? Icons.check_rounded
                      : Icons.circle_outlined,
                  size: 15,
                  color: granted ? Colors.green : kTextSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: kTextPrimary)),
              const Spacer(),
              Text(
                granted ? 'Granted' : 'Required',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: granted ? Colors.green : kTextSecondary,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

// Redirect to main shell after onboarding
class MainShellRedirect extends StatelessWidget {
  const MainShellRedirect({super.key});
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (_) => false);
    });
    return const Scaffold(
      backgroundColor: kSurface,
      body: Center(
        child: CircularProgressIndicator(color: kPurpleDark, strokeWidth: 2),
      ),
    );
  }
}