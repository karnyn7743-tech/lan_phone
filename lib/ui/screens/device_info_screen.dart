import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/messaging/message_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/signaling/signaling_service.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/permission_dialog.dart';
import 'audio_call_screen.dart';
import 'chat_screen.dart';
import 'notification_settings_screen.dart';
import 'video_call_screen.dart';

/// ============================================================
/// شاشة معلومات الجهاز
/// ============================================================
class DeviceInfoScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceInfoScreen({super.key, required this.device});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  bool _isLoading = true;
  int _messageCount = 0;
  int _callCount = 0;
  int? _firstSeen;
  bool _isFavorite = false;
  bool _isBlocked = false;
  bool _notifEnabled = true;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    try {
      final db = DatabaseHelper.instance;
      final deviceId = widget.device.deviceId;

      final results = await Future.wait([
        db.getMessageCountForPeer(deviceId),
        db.getCallCountForPeer(deviceId),
        db.getFirstSeenForDevice(deviceId),
        db.isFavorite(deviceId),
        db.isDeviceBlocked(deviceId),
      ]);

      // ✅ احصل على إعدادات الإشعارات
      final notifSettings =
          await db.getNotificationSettings(deviceId);

      if (!mounted) return;
      setState(() {
        _messageCount = results[0] as int;
        _callCount = results[1] as int;
        _firstSeen = results[2] as int?;
        _isFavorite = results[3] as bool;
        _isBlocked = results[4] as bool;
        _notifEnabled = (notifSettings['enabled'] as int?) == 1;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[DeviceInfo] loadStats error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === المكالمات ===
  // ============================================

  Future<void> _audioCall() async {
    final granted = await PermissionDialog.ensure(
      context,
      permissions: <ph.Permission>[ph.Permission.microphone],
      title: 'الميكروفون',
      message: 'نحتاج الميكروفون لإجراء المكالمات الصوتية',
      icon: Icons.mic,
    );
    if (!granted || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioCallScreen(
          peer: widget.device,
          isCaller: true,
        ),
      ),
    );
  }

  Future<void> _videoCall() async {
    final granted = await PermissionDialog.ensure(
      context,
      permissions: <ph.Permission>[
        ph.Permission.microphone,
        ph.Permission.camera,
      ],
      title: 'الكاميرا والميكروفون',
      message: 'نحتاجهما لإجراء مكالمات الفيديو',
      icon: Icons.videocam,
    );
    if (!granted || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          peer: widget.device,
          isCaller: true,
        ),
      ),
    );
  }

  void _openChat() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peer: widget.device),
      ),
    );
  }

  // ============================================
  // === إعدادات الإشعارات (جديد) ===
  // ============================================

  Future<void> _openNotificationSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationSettingsScreen(
          device: widget.device,
        ),
      ),
    );

    // أعد تحميل الإحصائيات (قد تغيّرت إعدادات الإشعارات)
    await _loadStats();
  }

  // ============================================
  // === تعديل الاسم ===
  // ============================================

  Future<void> _editName() async {
    final controller = TextEditingController(text: widget.device.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم الجهاز'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: 'مثال: هاتف أحمد',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName == null ||
        newName.isEmpty ||
        newName == widget.device.name) {
      return;
    }

    try {
      await DatabaseHelper.instance.updateDeviceName(
        widget.device.deviceId,
        newName,
      );

      if (!mounted) return;
      HapticFeedback.lightImpact();
      _showSnack('تم تحديث الاسم', isSuccess: true);
    } catch (e) {
      debugPrint('[DeviceInfo] editName error: $e');
      if (!mounted) return;
      _showSnack('تعذّر تحديث الاسم');
    }
  }

  // ============================================
  // === المفضلة ===
  // ============================================

  Future<void> _toggleFavorite() async {
    try {
      await DatabaseHelper.instance.toggleFavorite(
        widget.device.deviceId,
        !_isFavorite,
      );

      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _isFavorite = !_isFavorite);
      _showSnack(
        _isFavorite ? 'أُضيف للمفضلة' : 'أُزيل من المفضلة',
        isSuccess: true,
      );
    } catch (e) {
      debugPrint('[DeviceInfo] toggleFavorite error: $e');
    }
  }

  // ============================================
  // === الحظر ===
  // ============================================

  Future<void> _toggleBlock() async {
    final willBlock = !_isBlocked;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          willBlock ? Icons.block : Icons.lock_open_outlined,
          size: 40,
          color: willBlock ? AppTheme.errorColor : AppTheme.primaryColor,
        ),
        title: Text(willBlock ? 'حظر الجهاز' : 'إلغاء الحظر'),
        content: Text(
          willBlock
              ? 'لن تستقبل رسائل أو مكالمات من "${widget.device.name}".'
              : 'سيتمكن "${widget.device.name}" من مراسلتك والاتصال بك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  willBlock ? AppTheme.errorColor : AppTheme.primaryColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willBlock ? 'حظر' : 'إلغاء الحظر'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DatabaseHelper.instance.toggleBlock(
        widget.device.deviceId,
        willBlock,
      );

      if (!mounted) return;
      await context.read<MessageService>().refreshBlockedDevices();
      if (!mounted) return;
      await context.read<SignalingService>().refreshBlockedDevices();

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _isBlocked = willBlock);
      _showSnack(
        willBlock ? 'تم حظر الجهاز' : 'تم إلغاء الحظر',
        isSuccess: true,
      );
    } catch (e) {
      debugPrint('[DeviceInfo] toggleBlock error: $e');
    }
  }

  // ============================================
  // === الحذف ===
  // ============================================

  Future<void> _deleteDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          size: 40,
          color: AppTheme.errorColor,
        ),
        title: const Text('حذف الجهاز'),
        content: Text(
          'سيتم حذف "${widget.device.name}" مع كل محادثاته وسجل مكالماته.\n\n'
          'لا يمكن التراجع عن هذه العملية.',
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
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final discovery = context.read<DeviceDiscovery>();
      await discovery.removeDevice(widget.device.deviceId);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف "${widget.device.name}"'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e) {
      debugPrint('[DeviceInfo] delete error: $e');
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  void _showSnack(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppTheme.successColor : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('تم نسخ $label', isSuccess: true);
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = context.select<DeviceDiscovery, bool>(
      (d) => d.isDeviceOnline(widget.device.deviceId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('معلومات الجهاز'),
      ),
      body: ListView(
        children: [
          _buildHeader(isOnline),
          const SizedBox(height: 8),
          if (isOnline) _buildCallButtons(),
          const _SectionTitle(title: 'معلومات الشبكة'),
          _buildNetworkSection(isDark),
          if (!_isLoading) ...[
            const _SectionTitle(title: 'الإحصائيات'),
            _buildStatsSection(isDark),
          ],
          const _SectionTitle(title: 'القدرات'),
          _buildCapabilitiesSection(isDark),
          const _SectionTitle(title: 'الإجراءات'),
          _buildActionsSection(isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ============================================
  // === الرأس ===
  // ============================================

  Widget _buildHeader(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isOnline
                        ? [
                            AppTheme.primaryColor,
                            AppTheme.primaryColor.withOpacity(0.75),
                          ]
                        : [Colors.grey.shade400, Colors.grey.shade600],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isOnline
                              ? AppTheme.primaryColor
                              : Colors.grey)
                          .withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.device.name.isNotEmpty
                      ? widget.device.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_isFavorite)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.star,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (_isBlocked)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.block,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.device.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.device.hasValidNumber) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '#${widget.device.number}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                  letterSpacing: 1.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOnline ? AppTheme.successColor : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isOnline
                    ? 'متصل الآن'
                    : 'غير متصل • ${_formatLastSeen(widget.device.lastSeen)}',
                style: TextStyle(
                  fontSize: 14,
                  color: isOnline
                      ? AppTheme.successColor
                      : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================
  // === أزرار المكالمات ===
  // ============================================

  Widget _buildCallButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.call,
              label: 'مكالمة صوتية',
              color: AppTheme.successColor,
              onTap: _audioCall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              icon: Icons.videocam,
              label: 'مكالمة فيديو',
              color: AppTheme.primaryColor,
              onTap: _videoCall,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === معلومات الشبكة ===
  // ============================================

  Widget _buildNetworkSection(bool isDark) {
    return _Card(
      children: [
        _InfoTile(
          icon: Icons.wifi,
          title: 'عنوان IP',
          value: widget.device.ip,
          onCopy: () => _copyToClipboard(widget.device.ip, 'عنوان IP'),
        ),
        _InfoTile(
          icon: Icons.settings_ethernet,
          title: 'المنفذ',
          value: '${widget.device.port}',
        ),
        _InfoTile(
          icon: Icons.tag,
          title: 'معرّف الجهاز',
          value: widget.device.deviceId.length > 20
              ? '${widget.device.deviceId.substring(0, 20)}...'
              : widget.device.deviceId,
          onCopy: () => _copyToClipboard(
            widget.device.deviceId,
            'المعرّف',
          ),
        ),
      ],
    );
  }

  // ============================================
  // === الإحصائيات ===
  // ============================================

  Widget _buildStatsSection(bool isDark) {
    return _Card(
      children: [
        _InfoTile(
          icon: Icons.chat_bubble_outline,
          title: 'الرسائل المُتبادلة',
          value: '$_messageCount',
        ),
        _InfoTile(
          icon: Icons.call_outlined,
          title: 'المكالمات',
          value: '$_callCount',
        ),
        _InfoTile(
          icon: Icons.calendar_today_outlined,
          title: 'أول ظهور',
          value: _firstSeen != null
              ? _formatFullDate(_firstSeen!)
              : 'غير معروف',
        ),
        _InfoTile(
          icon: Icons.access_time,
          title: 'آخر ظهور',
          value: _formatLastSeen(widget.device.lastSeen),
        ),
      ],
    );
  }

  // ============================================
  // === القدرات ===
  // ============================================

  Widget _buildCapabilitiesSection(bool isDark) {
    final caps = widget.device.capabilities;

    return _Card(
      children: [
        _CapabilityTile(
          icon: Icons.chat_bubble_outline,
          label: 'الرسائل النصية',
          enabled: caps.contains('text'),
        ),
        _CapabilityTile(
          icon: Icons.mic,
          label: 'المكالمات الصوتية',
          enabled: caps.contains('voice'),
        ),
        _CapabilityTile(
          icon: Icons.videocam,
          label: 'مكالمات الفيديو',
          enabled: caps.contains('video'),
        ),
        _CapabilityTile(
          icon: Icons.attach_file,
          label: 'الوسائط والملفات',
          enabled: caps.contains('media'),
        ),
      ],
    );
  }

  // ============================================
  // === الإجراءات ===
  // ============================================

  Widget _buildActionsSection(bool isDark) {
    return _Card(
      children: [
        // فتح المحادثة
        _ActionTile(
          icon: Icons.chat_bubble_outline,
          label: 'فتح المحادثة',
          subtitle: 'عرض الرسائل المُتبادلة',
          onTap: _openChat,
        ),

        // ✅ إعدادات الإشعارات (جديد)
        _ActionTile(
          icon: _notifEnabled
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: 'إعدادات الإشعارات',
          subtitle: _notifEnabled
              ? 'الإشعارات مفعّلة — اضغط للتخصيص'
              : 'الإشعارات متوقفة',
          color: _notifEnabled ? null : AppTheme.warningColor,
          onTap: _openNotificationSettings,
        ),

        // تعديل الاسم
        _ActionTile(
          icon: Icons.edit_outlined,
          label: 'تعديل الاسم',
          subtitle: 'غيّر الاسم المعروض لهذا الجهاز',
          onTap: _editName,
        ),

        // المفضلة
        _ActionTile(
          icon: _isFavorite ? Icons.star : Icons.star_border,
          label: _isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
          subtitle: 'الاحتفاظ به في أعلى قائمة الأجهزة',
          color: _isFavorite ? Colors.amber : null,
          onTap: _toggleFavorite,
        ),

        // الحظر
        _ActionTile(
          icon: _isBlocked ? Icons.lock_open_outlined : Icons.block,
          label: _isBlocked ? 'إلغاء الحظر' : 'حظر الجهاز',
          subtitle: _isBlocked
              ? 'السماح بالرسائل والمكالمات'
              : 'منع الرسائل والمكالمات',
          color: _isBlocked ? null : AppTheme.errorColor,
          onTap: _toggleBlock,
        ),

        Divider(
          height: 1,
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),

        // الحذف
        _ActionTile(
          icon: Icons.delete_outline,
          label: 'حذف الجهاز',
          subtitle: 'إزالة مع كل محادثاته',
          color: AppTheme.errorColor,
          onTap: _deleteDevice,
        ),
      ],
    );
  }

  // ============================================
  // === أدوات الوقت ===
  // ============================================

  String _formatLastSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return 'منذ فترة طويلة';
  }

  String _formatFullDate(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('d MMM yyyy • h:mm a', 'ar').format(d);
  }
}

// ============================================================
// === عناصر مساعدة ===
// ============================================================

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onCopy;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
      trailing: onCopy != null
          ? IconButton(
              icon: const Icon(Icons.copy_outlined, size: 20),
              tooltip: 'نسخ',
              onPressed: onCopy,
            )
          : null,
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _CapabilityTile({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? AppTheme.primaryColor
            : (isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: enabled
              ? (isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary)
              : (isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary),
          fontWeight: enabled ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: Icon(
        enabled ? Icons.check_circle : Icons.cancel_outlined,
        color: enabled ? AppTheme.successColor : Colors.grey.shade500,
        size: 22,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveColor = color ??
        (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary);

    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(
        label,
        style: TextStyle(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_left,
        color: isDark
            ? AppTheme.darkTextSecondary
            : AppTheme.lightTextSecondary,
      ),
      onTap: onTap,
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
