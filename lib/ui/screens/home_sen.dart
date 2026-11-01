import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/services/broadcast_service.dart';
import '../../core/services/permission_service.dart';
import '../theme/app_theme.dart';
import 'broadcast_screen.dart';
import 'dialer_screen.dart';
import 'global_search_screen.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';
import 'tabs/conversations_tab.dart';
import 'tabs/devices_tab.dart';
import 'tabs/calls_tab.dart';

/// ============================================================
/// الشاشة الرئيسية
/// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _permissionsChecked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureDiscoveryPermissions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ============================================
  // === الأذونات ===
  // ============================================

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

  // ============================================
  // === البث الصوتي (جديد) ===
  // ============================================

  void _openBroadcast() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BroadcastScreen()),
    );
  }

  // ============================================
  // === البحث العالمي ===
  // ============================================

  void _openGlobalSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
    );
  }

  // ============================================
  // === QR ===
  // ============================================

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

  // ============================================
  // === الأزرار الأخرى ===
  // ============================================

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

  // ============================================
  // === FAB ===
  // ============================================

  void _onFabPressed() {
    _tabController.animateTo(2);
  }

  // ============================================
  // === قائمة إضافية ===
  // ============================================

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

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<DeviceDiscovery>();
    final broadcast = context.watch<BroadcastService>();
    final onlineCount = discovery.onlineDevices.length;
    final myNumber = discovery.deviceNumber;

    return Scaffold(
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
          // البحث
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'البحث',
            onPressed: _openGlobalSearch,
          ),

          // ✅ البث الصوتي (مع شارة حمراء إذا كان نشطًا)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.podcasts),
                tooltip: 'البث الصوتي',
                onPressed: _openBroadcast,
              ),
              if (broadcast.isBroadcasting)
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
              if (broadcast.isListening)
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

          // قائمة إضافية
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
    );
  }
}

// ============================================================
// === عناصر مساعدة ===
// ============================================================

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
