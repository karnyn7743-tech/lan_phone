import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/discovery/discovered_device.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة إعدادات الإشعارات لجهاز معين
/// ============================================================
class NotificationSettingsScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const NotificationSettingsScreen({
    super.key,
    required this.device,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  bool _isLoading = true;
  bool _enabled = true;
  bool _sound = true;
  bool _vibration = true;
  bool _hasChanges = false;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final settings = await DatabaseHelper.instance
          .getNotificationSettings(widget.device.deviceId);

      if (!mounted) return;
      setState(() {
        _enabled = (settings['enabled'] as int?) == 1;
        _sound = (settings['sound'] as int?) == 1;
        _vibration = (settings['vibration'] as int?) == 1;
        _isLoading = false;
        _hasChanges = false;
      });
    } catch (e) {
      debugPrint('[NotifSettings] load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === الحفظ ===
  // ============================================

  Future<void> _save() async {
    try {
      await DatabaseHelper.instance.upsertNotificationSettings(
        deviceId: widget.device.deviceId,
        enabled: _enabled,
        sound: _sound,
        vibration: _vibration,
      );

      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _hasChanges = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ الإعدادات'),
          backgroundColor: AppTheme.successColor,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[NotifSettings] save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حفظ الإعدادات'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // ============================================
  // === التبديلات ===
  // ============================================

  void _toggleEnabled(bool value) {
    HapticFeedback.selectionClick();
    setState(() {
      _enabled = value;
      _hasChanges = true;
    });
  }

  void _toggleSound(bool value) {
    HapticFeedback.selectionClick();
    setState(() {
      _sound = value;
      _hasChanges = true;
    });
  }

  void _toggleVibration(bool value) {
    HapticFeedback.selectionClick();
    setState(() {
      _vibration = value;
      _hasChanges = true;
    });
  }

  void _resetToDefaults() {
    setState(() {
      _enabled = true;
      _sound = true;
      _vibration = true;
      _hasChanges = true;
    });
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_hasChanges) {
          final save = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.save_outlined,
                size: 40,
                color: AppTheme.primaryColor,
              ),
              title: const Text('حفظ التغييرات؟'),
              content: const Text('هل تريد حفظ إعدادات الإشعارات؟'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('تجاهل'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          );

          if (!mounted) return;

          if (save == true) {
            await _save();
          }
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات الإشعارات'),
          actions: [
            // زر حفظ
            if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'حفظ',
                onPressed: _save,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryColor,
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // رأس الجهاز
                  _buildHeader(),

                  const SizedBox(height: 8),

                  // ============================================
                  // === الإشعارات ===
                  // ============================================
                  const _SectionTitle(title: 'الإشعارات'),
                  _buildNotificationsSection(),

                  // ============================================
                  // === الأصوات ===
                  // ============================================
                  const _SectionTitle(title: 'الأصوات والاهتزاز'),
                  _buildSoundSection(),

                  // ============================================
                  // === زر إعادة الضبط ===
                  // ============================================
                  const SizedBox(height: 16),
                  _buildResetButton(),

                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  // ============================================
  // === رأس الجهاز ===
  // ============================================

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.device.name.isNotEmpty
                  ? widget.device.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إشعارات من',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.device.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.device.hasValidNumber) ...[
                  const SizedBox(height: 4),
                  Text(
                    '#${widget.device.number}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                      letterSpacing: 1.0,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            _enabled ? Icons.notifications_active : Icons.notifications_off,
            color: Colors.white.withOpacity(0.9),
            size: 28,
          ),
        ],
      ),
    );
  }

  // ============================================
  // === قسم الإشعارات ===
  // ============================================

  Widget _buildNotificationsSection() {
    return _SettingsCard(
      children: [
        SwitchListTile(
          value: _enabled,
          onChanged: _toggleEnabled,
          title: const Text('تشغيل الإشعارات'),
          subtitle: Text(
            _enabled
                ? 'ستظهر إشعارات من هذا الجهاز'
                : 'لن تظهر أي إشعارات من هذا الجهاز',
            style: TextStyle(
              color: _enabled ? null : AppTheme.warningColor,
              fontWeight: _enabled ? null : FontWeight.w600,
            ),
          ),
          secondary: Icon(
            _enabled
                ? Icons.notifications_active
                : Icons.notifications_off,
            color: _enabled ? AppTheme.primaryColor : AppTheme.warningColor,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        if (!_enabled)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppTheme.warningColor,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الرسائل ستُسجَّل في المحادثة لكن بدون إشعار. '
                    'ستظهر فقط عند فتح التطبيق.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================
  // === قسم الأصوات ===
  // ============================================

  Widget _buildSoundSection() {
    return _SettingsCard(
      children: [
        SwitchListTile(
          value: _sound,
          onChanged: _enabled ? _toggleSound : null,
          title: const Text('الصوت'),
          subtitle: const Text('تشغيل نغمة إشعار'),
          secondary: Icon(
            _sound ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            color: _enabled ? null : Colors.grey,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        SwitchListTile(
          value: _vibration,
          onChanged: _enabled ? _toggleVibration : null,
          title: const Text('الاهتزاز'),
          subtitle: const Text('اهتزاز عند وصول إشعار'),
          secondary: Icon(
            _vibration
                ? Icons.vibration_outlined
                : Icons.phonelink_erase_outlined,
            color: _enabled ? null : Colors.grey,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        if (!_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'لا يمكن تعديل الأصوات عندما تكون الإشعارات متوقفة.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  // ============================================
  // === زر إعادة الضبط ===
  // ============================================

  Widget _buildResetButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: _resetToDefaults,
        icon: const Icon(Icons.refresh),
        label: const Text('إعادة الإعدادات الافتراضية'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          side: BorderSide(
            color: AppTheme.primaryColor.withOpacity(0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

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
