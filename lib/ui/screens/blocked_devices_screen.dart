import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/discovery/device_discovery.dart';
import '../../core/messaging/message_service.dart';
import '../../core/signaling/signaling_service.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة الأجهزة المحظورة
/// ============================================================
class BlockedDevicesScreen extends StatefulWidget {
  const BlockedDevicesScreen({super.key});

  @override
  State<BlockedDevicesScreen> createState() =>
      _BlockedDevicesScreenState();
}

class _BlockedDevicesScreenState extends State<BlockedDevicesScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  List<Map<String, dynamic>> _blockedDevices = [];
  bool _isLoading = true;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await DatabaseHelper.instance.getBlockedDevices();
      if (!mounted) return;
      setState(() {
        _blockedDevices = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Blocked] load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === إلغاء الحظر ===
  // ============================================

  Future<void> _unblock(Map<String, dynamic> device) async {
    final deviceId = device['device_id'] as String;
    final name = device['name'] as String? ?? 'الجهاز';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.lock_open_outlined,
          size: 40,
          color: AppTheme.primaryColor,
        ),
        title: const Text('إلغاء الحظر'),
        content: Text(
          'هل تريد إلغاء حظر "$name"؟\n'
          'سيتمكن من مراسلتك والاتصال بك مرة أخرى.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء الحظر'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1) حدّث قاعدة البيانات
      await DatabaseHelper.instance.toggleBlock(deviceId, false);

      // 2) حدّث cache في MessageService
      if (mounted) {
        await context.read<MessageService>().refreshBlockedDevices();
      }

      // 3) حدّث cache في SignalingService
      if (mounted) {
        await context.read<SignalingService>().refreshBlockedDevices();
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إلغاء حظر "$name"'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 2),
        ),
      );

      // 4) أعد التحميل
      await _load();
    } catch (e) {
      debugPrint('[Blocked] unblock error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر إلغاء الحظر'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجهزة المحظورة'),
        actions: [
          if (_blockedDevices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'إلغاء حظر الكل',
              onPressed: _confirmUnblockAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _blockedDevices.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _blockedDevices.length + 1,
                    separatorBuilder: (_, index) =>
                        index == 0 ? const SizedBox.shrink() : const Divider(height: 1, indent: 80),
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildHeader();
                      final device = _blockedDevices[index - 1];
                      return _BlockedDeviceTile(
                        device: device,
                        onUnblock: () => _unblock(device),
                      );
                    },
                  ),
                ),
    );
  }

  // ============================================
  // === الرأس (معلومات) ===
  // ============================================

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.errorColor.withOpacity(0.2),
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
              Icons.info_outline,
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
                Text(
                  '${_blockedDevices.length} جهاز محظور',
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
                  'لن تستقبل رسائل أو مكالمات من هذه الأجهزة',
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

  // ============================================
  // === حالة فارغة ===
  // ============================================

  Widget _buildEmpty() {
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
                Icons.shield_outlined,
                size: 52,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد أجهزة محظورة',
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
              'عند حظر أي جهاز، سيظهر في هذه القائمة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === إلغاء حظر الكل ===
  // ============================================

  Future<void> _confirmUnblockAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 40,
          color: AppTheme.warningColor,
        ),
        title: const Text('إلغاء حظر الكل'),
        content: Text(
          'سيتم إلغاء حظر ${_blockedDevices.length} جهاز.\n'
          'هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء الكل'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      for (final device in _blockedDevices) {
        await DatabaseHelper.instance.toggleBlock(
          device['device_id'] as String,
          false,
        );
      }

      if (!mounted) return;
      await context.read<MessageService>().refreshBlockedDevices();
      if (!mounted) return;
      await context.read<SignalingService>().refreshBlockedDevices();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء حظر جميع الأجهزة'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      await _load();
    } catch (e) {
      debugPrint('[Blocked] unblockAll error: $e');
    }
  }
}

// ============================================================
// === صف جهاز محظور ===
// ============================================================
class _BlockedDeviceTile extends StatelessWidget {
  final Map<String, dynamic> device;
  final VoidCallback onUnblock;

  const _BlockedDeviceTile({
    required this.device,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final deviceId = device['device_id'] as String;
    final name = device['name'] as String? ?? 'جهاز';
    final number = device['number'] as String? ?? '';
    final lastSeenMs = device['last_seen'] as int?;

    // حالة الاتصال الحقيقية
    final isOnline = context.select<DeviceDiscovery, bool>(
      (d) => d.isDeviceOnline(deviceId),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onUnblock,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          color: isDark ? AppTheme.darkSurface : Colors.white,
          child: Row(
            children: [
              // الأفاتار
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // شارة الحظر
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.block,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 14),

              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.lightTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (number.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$number',
                              style: const TextStyle(
                                fontSize: 10,
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
                          Icons.block,
                          size: 12,
                          color: AppTheme.errorColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'محظور',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isOnline) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.successColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'متصل الآن',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ] else if (lastSeenMs != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            'آخر ظهور ${_formatLastSeen(lastSeenMs)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // زر إلغاء الحظر
              Material(
                color: AppTheme.primaryColor.withOpacity(0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onUnblock,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.lock_open_outlined,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastSeen(int timestamp) {
    final diff =
        DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );

    if (diff.inMinutes < 1) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} ي';
  }
}
