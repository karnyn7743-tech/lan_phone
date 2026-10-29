import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../../core/discovery/device_discovery.dart';
import '../../../core/discovery/discovered_device.dart';
import '../../../core/messaging/message_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/signaling/signaling_service.dart';
import '../../../data/database/database_helper.dart';
import '../../theme/app_theme.dart';
import '../blocked_devices_screen.dart';
import '../chat_screen.dart';

/// ============================================================
/// تبويب الأجهزة
/// ============================================================
class DevicesTab extends StatelessWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceDiscovery>(
      builder: (context, discovery, _) {
        // ✅ اجلب قائمة المحظورين من MessageService
        final blockedIds = context.select<MessageService, Set<String>>(
          (m) => m.blockedDeviceIds,
        );

        final allDevices = discovery.devices
            .where((d) => !blockedIds.contains(d.deviceId))
            .toList();

        final onlineDevices =
            allDevices.where((d) => d.isOnline).toList();
        final offlineDevices =
            allDevices.where((d) => !d.isOnline).toList();

        if (!discovery.isRunning) {
          return const _LoadingState(
            message: 'جارٍ تشغيل خدمة الاكتشاف...',
          );
        }

        if (allDevices.isEmpty && blockedIds.isEmpty) {
          return _EmptyDevicesState(
            onRefresh: () => discovery.refreshNow(),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            discovery.refreshNow();
            await Future.delayed(const Duration(milliseconds: 800));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _StatusBar(
                online: onlineDevices.length,
                total: allDevices.length,
                localIp: discovery.localIp,
                myNumber: discovery.deviceNumber,
              ),

              // ✅ زر "المحظورون" إذا وُجدوا
              if (blockedIds.isNotEmpty) _buildBlockedBar(context, blockedIds.length),

              if (onlineDevices.isNotEmpty) ...[
                const _SectionHeader(title: 'الأجهزة المتصلة'),
                ...onlineDevices.map(
                  (d) => _DeviceTile(device: d, isOnline: true),
                ),
              ],

              if (offlineDevices.isNotEmpty) ...[
                const _SectionHeader(title: 'الأجهزة السابقة'),
                ...offlineDevices.map(
                  (d) => _DeviceTile(device: d, isOnline: false),
                ),
              ],

              if (allDevices.isEmpty && blockedIds.isNotEmpty)
                _buildOnlyBlockedState(),

              const SizedBox(height: 60),
            ],
          ),
        );
      },
    );
  }

  // ============================================
  // === شريط المحظورين ===
  // ============================================

  Widget _buildBlockedBar(BuildContext context, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BlockedDevicesScreen(),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.errorColor.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.block,
                  color: AppTheme.errorColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'الأجهزة المحظورة',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.errorColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count ${count == 1 ? "جهاز" : "أجهزة"} — اضغط للإدارة',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlyBlockedState() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 60,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'كل الأجهزة محظورة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ألغِ الحظر للتواصل مع الأجهزة',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// === شريط الحالة ===
// ============================================================
class _StatusBar extends StatelessWidget {
  final int online;
  final int total;
  final String localIp;
  final String myNumber;

  const _StatusBar({
    required this.online,
    required this.total,
    required this.localIp,
    required this.myNumber,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppTheme.primaryColor.withOpacity(0.25),
                  AppTheme.primaryColor.withOpacity(0.08),
                ]
              : [
                  AppTheme.primaryColor.withOpacity(0.12),
                  AppTheme.primaryColor.withOpacity(0.04),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'رقمي',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  myNumber.isEmpty ? '----' : myNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  online == 0
                      ? 'لا توجد أجهزة متصلة'
                      : '$online ${online == 1 ? "جهاز متصل" : "أجهزة متصلة"}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localIp.isEmpty
                      ? 'جارٍ اكتشاف الشبكة...'
                      : 'IP: $localIp',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === رأس قسم ===
// ============================================================
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
    );
  }
}

// ============================================================
// === صف جهاز ===
// ============================================================
class _DeviceTile extends StatelessWidget {
  final DiscoveredDevice device;
  final bool isOnline;

  const _DeviceTile({
    required this.device,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isOnline ? () => _openChat(context) : null,
        onLongPress: () => _showOptions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _DeviceAvatar(
                  name: device.name,
                  isOnline: isOnline,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTheme.darkTextPrimary
                                    : AppTheme.lightTextPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (device.hasValidNumber) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#${device.number}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.wifi,
                            size: 12,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              isOnline
                                  ? device.ip
                                  : 'آخر ظهور ${_formatLastSeen(device.lastSeen)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (isOnline) ...[
                  _IconActionButton(
                    icon: Icons.call_outlined,
                    tooltip: 'مكالمة صوتية',
                    color: AppTheme.successColor,
                    onTap: () => _callFromTile(context, isVideo: false),
                  ),
                  const SizedBox(width: 6),
                  _IconActionButton(
                    icon: Icons.videocam_outlined,
                    tooltip: 'مكالمة فيديو',
                    color: AppTheme.primaryColor,
                    onTap: () => _callFromTile(context, isVideo: true),
                  ),
                  const SizedBox(width: 4),
                ],

                Icon(
                  Icons.chevron_left,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // === فتح محادثة ===
  // ============================================
  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peer: device),
      ),
    );
  }

  // ============================================
  // === قائمة الخيارات ===
  // ============================================
  void _showOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
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
              // عنوان
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.devices,
                      size: 20,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // فتح المحادثة
              if (isOnline)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('فتح المحادثة'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openChat(context);
                  },
                ),

              // ✅ حظر
              ListTile(
                leading: const Icon(
                  Icons.block,
                  color: AppTheme.errorColor,
                ),
                title: const Text(
                  'حظر الجهاز',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
                subtitle: const Text(
                  'منع المراسلة والمكالمات من هذا الجهاز',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmBlock(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmBlock(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.block,
          size: 40,
          color: AppTheme.errorColor,
        ),
        title: const Text('حظر الجهاز'),
        content: Text(
          'هل تريد حظر "${device.name}"؟\n\n'
          'لن تستقبل رسائل أو مكالمات منه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حظر'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DatabaseHelper.instance.toggleBlock(device.deviceId, true);

      if (!context.mounted) return;
      await context.read<MessageService>().refreshBlockedDevices();
      if (!context.mounted) return;
      await context.read<SignalingService>().refreshBlockedDevices();

      if (!context.mounted) return;
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حظر "${device.name}"'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[Devices] block error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر الحظر'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // ============================================
  // === بدء مكالمة ===
  // ============================================
  Future<void> _callFromTile(
    BuildContext context, {
    required bool isVideo,
  }) async {
    final permissions = isVideo
        ? <ph.Permission>[
            ph.Permission.microphone,
            ph.Permission.camera,
          ]
        : <ph.Permission>[ph.Permission.microphone];

    final granted = await PermissionService.requestAll(permissions);
    if (!granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('نحتاج الأذونات لبدء المكالمة'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peer: device),
      ),
    );
  }

  String _formatLastSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} ي';
  }
}

// ============================================================
// === الأفاتار ===
// ============================================================
class _DeviceAvatar extends StatelessWidget {
  final String name;
  final bool isOnline;

  const _DeviceAvatar({
    required this.name,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isOnline
                  ? [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.75),
                    ]
                  : [
                      Colors.grey.shade500,
                      Colors.grey.shade700,
                    ],
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.successColor : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// === زر أيقونة صغير ===
// ============================================================
class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.15),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// === حالة فارغة ===
// ============================================================
class _EmptyDevicesState extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptyDevicesState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_tethering,
                size: 52,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد أجهزة على الشبكة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تأكد من أن الأجهزة الأخرى:\n'
              '• مفتوحة على نفس التطبيق\n'
              '• متصلة بنفس شبكة الواي فاي',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.6),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة البحث'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// === حالة التحميل ===
// ============================================================
class _LoadingState extends StatelessWidget {
  final String message;

  const _LoadingState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}
