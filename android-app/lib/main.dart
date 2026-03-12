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
import 'screens/contacts_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/normal_call_screen.dart';
import 'screens/call_screening_screen.dart';
import 'services/notification_service.dart';

/// Global navigator key — used to push screening screen from MethodChannel callbacks
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  static const _callControlChannel = MethodChannel('com.zentra.dialer/call_control');

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
      } else if (call.method == 'callStarted') {
        final number = call.arguments['number'] as String? ?? '';
        final state = call.arguments['state'] as int? ?? 0;
        ref.read(callManagerProvider.notifier).onCallStarted(number, state);
      } else if (call.method == 'callActive') {
        ref.read(callManagerProvider.notifier).onCallActive();
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

    // Call control channel — incoming screening calls from Kotlin
    _callControlChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingScreeningCall') {
        final args = call.arguments as Map;
        final callerNumber = args['caller_number'] as String? ?? '';
        final callId = args['call_id'] as String? ?? '';
        if (callerNumber.isNotEmpty) {
          ref.read(callManagerProvider.notifier)
              .onIncomingScreeningCall(callerNumber, callId);
          // MainShell Stack overlay shows CallScreeningScreen automatically
          // when state is incoming/active — no push needed here.
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Zentra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDBB8FF), // Primary accent: light purple
          primary: const Color(0xFFDBB8FF),
          surface: Colors.white,
          onSurface: const Color(0xFF1F2937), // Dark text
          primaryContainer: const Color(0xFFF9FAFB), // Very light gray card bg
          onSurfaceVariant: const Color(0xFF6B7280), // Secondary text
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Inter', // Assuming Inter based on modern SaaS UI
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1F2937)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
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
    ContactsScreen(),
    CallHistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final callState = ref.watch(callManagerProvider);
        final showCallUI = callState.state == CallState.ringing_normal || 
                           callState.state == CallState.outgoing ||
                           callState.state == CallState.active_normal;
        final showScreeningUI = callState.state == CallState.incoming ||
                                callState.state == CallState.active;

        return Stack(
          children: [
            Scaffold(
              body: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
                ),
                child: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.shield_outlined),
                      selectedIcon: Icon(Icons.shield_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dialpad_outlined),
                      selectedIcon: Icon(Icons.dialpad_rounded),
                      label: 'Dialer',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.contacts_outlined),
                      selectedIcon: Icon(Icons.contacts_rounded),
                      label: 'Contacts',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      selectedIcon: Icon(Icons.history_rounded),
                      label: 'History',
                    ),
                  ],
                ),
              ),
            ),
            if (showCallUI)
              const Positioned.fill(
                child: NormalCallScreen(),
              ),
            if (showScreeningUI && callState.activeSession != null)
              Positioned.fill(
                child: CallScreeningScreen(
                  callerNumber: callState.activeSession!.number,
                  callId: callState.activeSession!.callId,
                ),
              ),
          ],
        );
      },
    );
  }
}