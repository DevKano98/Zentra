import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'core/call_manager.dart';
import 'screens/home_screen.dart';
import 'screens/dialer_screen.dart';
import 'screens/call_history_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_complete') ?? false;

  await NotificationService.instance.initialize();

  runApp(
    ProviderScope(
      child: ZentraApp(showOnboarding: !onboardingDone),
    ),
  );
}

class ZentraApp extends ConsumerStatefulWidget {
  final bool showOnboarding;
  const ZentraApp({super.key, required this.showOnboarding});

  @override
  ConsumerState<ZentraApp> createState() => _ZentraAppState();
}

class _ZentraAppState extends ConsumerState<ZentraApp> {
  final MethodChannel _screeningChannel = const MethodChannel(kChannelScreening);
  final MethodChannel _audioChannel = const MethodChannel(kChannelAudio);
  final MethodChannel _callChannel = const MethodChannel(kChannelCall);
  final MethodChannel _notificationsChannel = const MethodChannel(kChannelNotifications);
  final MethodChannel _setupChannel = const MethodChannel(kChannelSetup);

  @override
  void initState() {
    super.initState();
    _setupChannelHandlers();
  }

  void _setupChannelHandlers() {
    // Screening channel — incoming unknown calls
    _screeningChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingCall') {
        final number = call.arguments['number'] as String? ?? '';
        ref.read(callManagerProvider.notifier).onIncomingCall(number);
      }
    });

    // Audio channel — audio chunks from native
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'audioChunk') {
        final data = call.arguments['data'] as Uint8List?;
        if (data != null) {
          ref.read(callManagerProvider.notifier).onAudioChunk(data);
        }
      } else if (call.method == 'callEnded') {
        ref.read(callManagerProvider.notifier).onCallEnded();
      }
    });

    // Notifications channel — delivery app notifications
    _notificationsChannel.setMethodCallHandler((call) async {
      if (call.method == 'deliveryNotification') {
        // Handle delivery notifications if needed
        debugPrint('Delivery notification: ${call.arguments}');
      }
    });

    // Setup channel — default dialer result callback
    _setupChannel.setMethodCallHandler((call) async {
      if (call.method == 'defaultDialerResult') {
        final isDefault = call.arguments['isDefault'] as bool? ?? false;
        debugPrint('Default dialer set: $isDefault');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zentra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter',
      ),
      home: widget.showOnboarding ? const OnboardingScreen() : const MainShell(),
      routes: {
        '/main': (_) => const MainShell(),
        '/onboarding': (_) => const OnboardingScreen(),
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    DialerScreen(),
    CallHistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        backgroundColor: colorScheme.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.dialpad_outlined),
            selectedIcon: Icon(Icons.dialpad),
            label: 'Dialer',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}