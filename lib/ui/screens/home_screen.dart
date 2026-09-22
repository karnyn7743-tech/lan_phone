import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/services/broadcast_service.dart';
import '../../core/services/permission_service.dart';
import '../theme/app_theme.dart';
import 'audio_call_screen.dart';
import 'broadcast_screen.dart';
import 'dialer_screen.dart';
import 'global_search_screen.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';
import 'tabs/calls_tab.dart';
import 'tabs/conversations_tab.dart';
import 'tabs/devices_tab.dart';
import 'video_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _permissionsChecked = false;
  DateTime? _lastBackPressTime;
  StreamSubscription<RtcEvent>? _rtcSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureDiscoveryPermissions();
      _listenToRtcEvents();
    });
  }

  /// الاستماع لأحداث RTC للتنقل التلقائي لشاشة المكالمات عند القبول أو الاستلام
  void _listenToRtcEvents() {
    final rtc = context.read<RtcService>();
    _rtcSubscription?.cancel();
    _rtcSubscription = rtc.events.listen((event) {
      if (!mounted) return;

      // عند استلام حدث قبول المكالمة أو مكالمة واردة، ننتقل فوراً للشاشة
      if (event.type == RtcEventType.callAccepted || event.type == RtcEventType.incomingCall) {
        _navigateToCallScreen(event);
      }
    });
  }

  void _navigateToCallScreen(RtcEvent event) {
    // البحث عن الجهاز المكتشف باستخدام المعرف الفريد للحصول على بياناته المسجلة
    final discovery = context.read<DeviceDiscovery>();
    final matchedDevice = discovery.onlineDevices.firstWhere(
      (d) => d.deviceId == event.peerDeviceId,
      orElse: () => DiscoveredDevice(
        deviceId: event.peerDeviceId,
        name: event.peerName,
        number: event.peerDeviceId,
        ip: '',
        port: 0,
        capabilities: const [],
        isOnline: true, // <-- أُضيفت هنا
        lastSeen: DateTime.now(),
      ),
    );

    final peer = DiscoveredDevice(
      deviceId: event.peerDeviceId,
      name: event.peerName,
      number: matchedDevice.number,
      ip: matchedDevice.ip,
      port: matchedDevice.port,
      capabilities: matchedDevice.capabilities,
      isOnline: matchedDevice.isOnline, // <-- أُضيفت هنا
      lastSeen: DateTime.now(),
    );

    if (event.callType == AppConstants.callTypeVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            peer: peer,
            isCaller: false,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(
            peer: peer,
            isCaller: false,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _rtcSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _ensureDiscoveryPermissions() async {
    if (_permissionsChecked) return;
    _permissionsChecked = true;

    final ok = await PermissionService.requestDiscovery();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'بدون إذن الموقع والواي فاي، لن يعمل اكتشاف الأجهزة',
          ),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'الإعدادات',
            textColor: Colors.white,
            onPressed: () => PermissionService.openAppSettings(),
          ),
        ),
      );
    }
  }

  void _openBroadcast() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BroadcastScreen()),
    );
  }

  void _openGlobalSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
    );
  }

  void _showQrOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'الاقتران عبر QR',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'شارك رقمك أو أضف جهازًا آخر فورًا',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _QrOption(
                      icon: Icons.qr_code_2,
                      label: 'عرض رمزي',
                      subtitle: 'ليراه الآخرون',
                      color: AppTheme.primaryColor,
                      onTap: () {
                        Navigator.pop(ctx);
                        _openQrDisplay();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QrOption(
                      icon: Icons.qr_code_scanner,
                      label: 'مسح رمز',
                      subtitle: 'لإضافة جهاز',
                      color: const Color(0xFF25D366),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openQrScanner();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQrDisplay() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrDisplayScreen()),
    );
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result != null && mounted) {
      _tabController.animateTo(2);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة الجهاز بنجاح'),
          backgroundColor: AppTheme.successColor,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openDialer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DialerScreen()),
    );
  }

  void _onFabPressed() {
    _tabController.animateTo(2);
  }

  void _showMoreMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.podcasts,
                  color: AppTheme.primaryColor,
                ),
                title: const Text('البث الصوتي المباشر'),
                subtitle: const Text('ابث صوتك لكل الأجهزة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBroadcast();
                },
              ),
              ListTile(
                leading: const Icon(Icons.dialpad),
                title: const Text('الاتصال برقم'),
                subtitle: const Text('اتصل بجهاز عبر رقمه'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDialer();
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('الاقتران بـ QR'),
                subtitle: const Text('عرض/مسح رمز الاقتران'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQrOptions();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('الإعدادات'),
                subtitle: const Text('إعدادات التطبيق'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = context.select<DeviceDiscovery, int>(
      (d) => d.onlineDevices.length,
    );
    final myNumber = context.select<DeviceDiscovery, String>(
      (d) => d.deviceNumber,
    );

    final isBroadcasting = context.select<BroadcastService, bool>(
      (b) => b.isBroadcasting,
    );
    final isListening = context.select<BroadcastService, bool>(
      (b) => b.isListening,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اضغط مرة أخرى للخروج من التطبيق'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Text(AppConstants.appName),
              if (myNumber.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    myNumber,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              const Tab(
                child: _TabContent(
                  icon: Icons.chat_bubble_outline,
                  label: 'المحادثات',
                ),
              ),
              const Tab(
                child: _TabContent(
                  icon: Icons.call_outlined,
                  label: 'المكالمات',
                ),
              ),
              Tab(
                child: _TabContent(
                  icon: Icons.devices_outlined,
                  label: 'الأجهزة',
                  badge: onlineCount > 0 ? onlineCount : null,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'البحث',
              onPressed: _openGlobalSearch,
            ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.podcasts),
                  tooltip: 'البحث الصوتي',
                  onPressed: _openBroadcast,
                ),
                if (isBroadcasting)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                if (isListening)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'المزيد',
              onPressed: _showMoreMenu,
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [
            ConversationsTab(),
            CallsTab(),
            DevicesTab(),
          ],
        ),
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final showFab = _tabController.index != 1;
            return AnimatedScale(
              scale: showFab ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton(
                onPressed: _onFabPressed,
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                tooltip: 'محادثة جديدة',
                child: const Icon(Icons.edit_outlined),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? badge;

  const _TabContent({
    required this.icon,
    required this.label,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
        if (badge != null && badge! > 0) ...[
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: AppTheme.errorColor,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              badge! > 99 ? '99+' : badge.toString(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QrOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QrOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
