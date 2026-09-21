import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/discovery/device_discovery.dart';
import 'core/discovery/discovered_device.dart';
import 'core/messaging/message_service.dart';
import 'core/providers/theme_provider.dart';
import 'core/rtc/rtc_service.dart';
import 'core/services/activation_service.dart';
import 'core/services/app_lifecycle_service.dart';
import 'core/services/broadcast_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/lock_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/permission_service.dart';
import 'core/services/ringtone_service.dart';
import 'core/signaling/signaling_service.dart';
import 'data/database/database_helper.dart';
import 'ui/screens/activation_screen.dart';
import 'ui/screens/audio_call_screen.dart';
import 'ui/screens/broadcast_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/video_call_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/incoming_broadcast_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    await WebRTC.initialize();
    debugPrint('[main] ✅ WebRTC initialized');
  } catch (e) {
    debugPrint('[main] WebRTC init error: $e');
  }

  try {
    await DatabaseHelper.instance.init();
  } catch (e) {
    debugPrint('[main] Database init error: $e');
  }

  try {
    await LocalNotificationService.instance.init();
    debugPrint('[main] Local notifications initialized');
  } catch (e) {
    debugPrint('[main] Local notifications init error: $e');
  }

  try {
    await PermissionService.requestEssentialAtStartup();
  } catch (e) {
    debugPrint('[main] Permission request error: $e');
  }

  runApp(const LanPhoneApp());
}

class LanPhoneApp extends StatelessWidget {
  const LanPhoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProvider<RingtoneService>(
          create: (_) => RingtoneService()..load(),
        ),
        ChangeNotifierProvider<AppLifecycleService>(
          create: (_) => AppLifecycleService(),
        ),
        ChangeNotifierProvider<LockService>(
          create: (_) => LockService(),
        ),
        ChangeNotifierProvider<ActivationService>(
          create: (_) => ActivationService(),
        ),
        ChangeNotifierProvider<NotificationService>(
          create: (_) => NotificationService(),
        ),
        ChangeNotifierProvider<DeviceDiscovery>(
          create: (_) => DeviceDiscovery()..start(),
        ),
        ChangeNotifierProxyProvider<DeviceDiscovery, SignalingService>(
          create: (_) => SignalingService()..start(),
          update: (_, discovery, signaling) {
            final service = signaling ?? SignalingService()..start();
            service.attachDiscovery(discovery);
            return service;
          },
        ),
        ChangeNotifierProxyProvider2<SignalingService, NotificationService, RtcService>(
          create: (_) => RtcService(),
          update: (_, signaling, notification, rtc) {
            final service = rtc ?? RtcService();
            service.attachSignaling(signaling);
            service.attachNotification(notification);
            return service;
          },
        ),
        ChangeNotifierProxyProvider2<SignalingService, DeviceDiscovery, BroadcastService>(
          create: (_) => BroadcastService(),
          update: (_, signaling, discovery, broadcast) {
            final service = broadcast ?? BroadcastService();
            service.attach(
              signaling: signaling,
              discovery: discovery,
            );
            return service;
          },
        ),
        ChangeNotifierProxyProvider3<DeviceDiscovery, SignalingService, AppLifecycleService, MessageService>(
          create: (_) => MessageService(),
          update: (_, discovery, signaling, lifecycle, messages) {
            final service = messages ?? MessageService();
            service.attach(discovery, signaling);
            service.attachLifecycle(lifecycle);
            return service;
          },
        ),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  StreamSubscription<RtcEvent>? _rtcSub;
  StreamSubscription<BroadcastEvent>? _broadcastSub;

  RtcService? _rtc;
  BroadcastService? _broadcastService;
  DeviceDiscovery? _discovery;

  bool _callScreenOpen = false;
  bool _broadcastDialogOpen = false;
  bool _broadcastScreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
      _setupNotificationTapHandler();
      _setupBroadcastListener();
    });
  }

  @override
  void dispose() {
    _rtcSub?.cancel();
    _broadcastSub?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    if (!mounted) return;
    _rtc = context.read<RtcService>();
    _discovery = context.read<DeviceDiscovery>();
    _rtcSub = _rtc!.events.listen(_onRtcEvent);
  }

  void _setupNotificationTapHandler() {
    LocalNotificationService.instance.onMessageTap = (peerDeviceId, messageId) {
      _openChatFromNotification(peerDeviceId, messageId);
    };
  }

  void _setupBroadcastListener() {
    if (!mounted) return;
    _broadcastService = context.read<BroadcastService>();
    _broadcastSub = _broadcastService!.events.listen(_onBroadcastEvent);
  }

  void _openChatFromNotification(String peerDeviceId, String? messageId) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final peer = _discovery?.getDevice(peerDeviceId);
    if (peer == null) return;

    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peer: peer,
          highlightMessageId: messageId,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _onRtcEvent(RtcEvent event) {
    switch (event.type) {
      case RtcEventType.incomingCall:
        break;
      case RtcEventType.callAccepted:
        _openCallScreen(event);
        break;
      case RtcEventType.callEnded:
        if (_callScreenOpen) {
          final nav = navigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          }
        }
        _callScreenOpen = false;
        break;
      default:
        break;
    }
  }

  void _openCallScreen(RtcEvent event) {
    if (_callScreenOpen) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // استخراج جهاز المتصل مع دمج بيانات الاسم الصحيحة لمنع بقاء الاسم القديم أو المجهول
    final discovered = _discovery?.getDevice(event.peerDeviceId);
    final peer = discovered ??
        DiscoveredDevice(
          deviceId: event.peerDeviceId,
          number: '',
          name: _rtc?.peerName.isNotEmpty == true
              ? _rtc!.peerName
              : (event.peerName.isNotEmpty ? event.peerName : 'جهاز محلي'),
          ip: '',
          port: 0,
          capabilities: const ['voice', 'video'],
          lastSeen: DateTime.now(),
          isOnline: true,
        );

    _callScreenOpen = true;

    // تمرير حالة هل المستخدم هو البادئ بالمكالمة (isCaller) بدقة
    final bool isCaller = _rtc?.isCaller ?? false;

    final Widget screen = event.callType == AppConstants.callTypeVideo
        ? VideoCallScreen(peer: peer, isCaller: isCaller)
        : AudioCallScreen(peer: peer, isCaller: isCaller);

    nav.push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      _callScreenOpen = false;
    });
  }

  void _onBroadcastEvent(BroadcastEvent event) {
    switch (event.type) {
      case BroadcastEventType.invitation:
        _showBroadcastInvitation(event);
        break;
      case BroadcastEventType.ended:
        _handleBroadcastEnded(event);
        break;
      case BroadcastEventType.disconnected:
        _handleBroadcastDisconnected(event);
        break;
      case BroadcastEventType.audioReceived:
        break;
    }
  }

  void _showBroadcastInvitation(BroadcastEvent event) {
    final lockService = context.read<LockService>();
    if (lockService.isLocked) {
      _broadcastService?.rejectBroadcast(event.broadcastId, event.peerDeviceId);
      return;
    }

    if (_broadcastDialogOpen || _callScreenOpen || _broadcastScreenOpen) {
      _broadcastService?.rejectBroadcast(event.broadcastId, event.peerDeviceId);
      return;
    }

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    _broadcastDialogOpen = true;

    showDialog(
      context: nav.overlay!.context,
      barrierDismissible: false,
      builder: (_) => IncomingBroadcastDialog(
        event: event,
        onResult: (accept) {
          _broadcastDialogOpen = false;
          if (accept) {
            _acceptBroadcast(event);
          } else {
            _broadcastService?.rejectBroadcast(event.broadcastId, event.peerDeviceId);
          }
        },
      ),
    ).then((_) {
      _broadcastDialogOpen = false;
    });
  }

  Future<void> _acceptBroadcast(BroadcastEvent event) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final ok = await _broadcastService!.acceptBroadcast(
      broadcastId: event.broadcastId,
      broadcasterDeviceId: event.peerDeviceId,
      broadcasterName: event.peerName,
      sdp: event.sdp ?? '',
      sdpType: event.sdpType ?? 'offer',
    );

    if (!ok) {
      if (nav.overlay?.context != null) {
        ScaffoldMessenger.of(nav.overlay!.context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر الانضمام للبث'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    _openBroadcastScreen();
  }

  void _handleBroadcastEnded(BroadcastEvent event) {
    if (_broadcastService?.isBroadcasting ?? false) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (_broadcastScreenOpen) {
      nav.pop();
      _broadcastScreenOpen = false;
    }

    if (nav.overlay?.context != null) {
      ScaffoldMessenger.of(nav.overlay!.context).showSnackBar(
        SnackBar(
          content: Text('انتهى بث ${event.peerName}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleBroadcastDisconnected(BroadcastEvent event) {
    if (!(_broadcastService?.isListening ?? false)) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (_broadcastScreenOpen) {
      nav.pop();
      _broadcastScreenOpen = false;
    }

    if (nav.overlay?.context != null) {
      ScaffoldMessenger.of(nav.overlay!.context).showSnackBar(
        SnackBar(
          content: Text('انقطع الاتصال ببث ${event.peerName}'),
          backgroundColor: AppTheme.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openBroadcastScreen() {
    if (_broadcastScreenOpen) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    _broadcastScreenOpen = true;

    nav.push(
      MaterialPageRoute(
        builder: (_) => const BroadcastScreen(),
      ),
    ).then((_) {
      _broadcastScreenOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return _AppGates(child: child ?? const SizedBox.shrink());
      },
      home: const SplashScreen(),
    );
  }
}

class _AppGates extends StatelessWidget {
  final Widget child;

  const _AppGates({required this.child});

  @override
  Widget build(BuildContext context) {
    final activation = context.watch<ActivationService>();

    if (activation.checking) {
      return const _LoadingGate();
    }

    if (!activation.activated) {
      return const ActivationScreen();
    }

    final locked = context.select<LockService, bool>((s) => s.isLocked);
    final inCall = context.select<RtcService, bool>((r) => r.isInCall);

    return Stack(
      children: [
        child,
        if (locked && !inCall)
          const Positioned.fill(
            child: LockScreen(),
          ),
      ],
    );
  }
}

class _LoadingGate extends StatelessWidget {
  const _LoadingGate();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A1A1F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                AppTheme.primaryColor,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'جارٍ التحقق...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
