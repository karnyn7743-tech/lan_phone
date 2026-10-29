import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/discovery/device_discovery.dart';
import '../../../core/services/permission_service.dart';
import '../../../data/database/database_helper.dart';
import '../../theme/app_theme.dart';
import '../audio_call_screen.dart';
import '../video_call_screen.dart';

/// ============================================================
/// تبويب سجل المكالمات
/// ============================================================
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  List<Map<String, dynamic>> _callLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLogs();
    });
  }

  Future<void> _loadLogs() async {
    try {
      final rows = await DatabaseHelper.instance.getAllCallLogs();
      if (!mounted) return;
      setState(() {
        _callLogs = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _callBack(Map<String, dynamic> log) async {
    final peerId = log['peer_device_id'] as String;
    final callType = log['type'] as String? ?? AppConstants.callTypeAudio;

    final discovery = context.read<DeviceDiscovery>();
    final peer = discovery.getDevice(peerId);

    if (peer == null || !peer.isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الجهاز غير متصل حاليًا')),
        );
      }
      return;
    }

    // ✅ استخدام ph.Permission
    final permissions = callType == AppConstants.callTypeVideo
        ? <ph.Permission>[
            ph.Permission.microphone,
            ph.Permission.camera,
          ]
        : <ph.Permission>[ph.Permission.microphone];

    final ok = await PermissionService.requestAll(permissions);
    if (!ok || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => callType == AppConstants.callTypeVideo
            ? VideoCallScreen(peer: peer, isCaller: true)
            : AudioCallScreen(peer: peer, isCaller: true),
      ),
    );

    // أعِد التحميل عند العودة
    _loadLogs();
  }

  Future<void> _deleteLog(String callId) async {
    await DatabaseHelper.instance.deleteCallLog(callId);
    await _loadLogs();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح السجل'),
        content: const Text('هل تريد مسح كل سجل المكالمات؟'),
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
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final db = DatabaseHelper.instance;
      for (final log in _callLogs) {
        await db.deleteCallLog(log['call_id'] as String);
      }
      await _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_callLogs.isEmpty) {
      return const _EmptyCallsState();
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: Column(
        children: [
          // ============================================
          // === رأس مع زر المسح ===
          // ============================================
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'آخر ${_callLogs.length} مكالمة',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('مسح الكل'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                  ),
                ),
              ],
            ),
          ),

          // ============================================
          // === قائمة السجل ===
          // ============================================
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _callLogs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 78),
              itemBuilder: (context, index) {
                final log = _callLogs[index];
                return _CallLogTile(
                  log: log,
                  onTap: () => _callBack(log),
                  onLongPress: () => _deleteLog(log['call_id'] as String),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === صف سجل مكالمة ===
// ============================================================
class _CallLogTile extends StatelessWidget {
  final Map<String, dynamic> log;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CallLogTile({
    required this.log,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final peerId = log['peer_device_id'] as String;
    final peerName = log['peer_name'] as String? ?? 'جهاز';
    final type = log['type'] as String? ?? AppConstants.callTypeAudio;
    final direction = log['direction'] as String? ?? 'outgoing';
    final state = log['state'] as String? ?? '';
    final startedAt = log['started_at'] as int? ?? 0;
    final duration = log['duration_seconds'] as int? ?? 0;

    final peer = context.select<DeviceDiscovery, bool>(
      (d) => d.isDeviceOnline(peerId),
    );

    // لون وأيقونة حسب نوع الاتجاه والحالة
    final (icon, iconColor) = _iconFor(direction, state);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ============================================
              // === الأفاتار ===
              // ============================================
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: peer
                            ? [
                                AppTheme.primaryColor,
                                AppTheme.primaryColor.withOpacity(0.75),
                              ]
                            : [Colors.grey.shade400, Colors.grey.shade600],
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (peer)
                    Positioned(
                      bottom: 1,
                      right: 1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 14),

              // ============================================
              // === المعلومات ===
              // ============================================
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      peerName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: state == 'missed' || state == 'declined'
                            ? AppTheme.errorColor
                            : (isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.lightTextPrimary),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(icon, size: 14, color: iconColor),
                        const SizedBox(width: 5),
                        Icon(
                          type == AppConstants.callTypeVideo
                              ? Icons.videocam_outlined
                              : Icons.call_outlined,
                          size: 14,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${_formatTime(startedAt)}'
                            '${duration > 0 ? " • ${_formatDuration(duration)}" : ""}',
                            style: TextStyle(
                              fontSize: 13,
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

              // ============================================
              // === زر الاتصال ===
              // ============================================
              Icon(
                type == AppConstants.callTypeVideo
                    ? Icons.videocam
                    : Icons.call,
                color: peer
                    ? AppTheme.primaryColor
                    : (isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _iconFor(String direction, String state) {
    if (state == 'missed') {
      return (Icons.call_missed, AppTheme.errorColor);
    }
    if (state == 'declined') {
      return (Icons.call_end, AppTheme.errorColor);
    }
    if (direction == 'incoming') {
      return (Icons.call_received, AppTheme.successColor);
    }
    return (Icons.call_made, AppTheme.primaryColor);
  }

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    final time = DateFormat('h:mm a', 'ar').format(d);
    if (diff == 0) return 'اليوم $time';
    if (diff == 1) return 'أمس $time';
    if (diff < 7) return '${DateFormat('EEEE', 'ar').format(d)} $time';
    return DateFormat('d/M/yyyy', 'ar').format(d);
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}ث';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m < 60) return '$mد $sث';
    final h = m ~/ 60;
    return '$hس ${m % 60}د';
  }
}

// ============================================================
// === حالة فارغة ===
// ============================================================
class _EmptyCallsState extends StatelessWidget {
  const _EmptyCallsState();

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
                Icons.call_outlined,
                size: 52,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد مكالمات',
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
              'سجل المكالمات الصوتية والمرئية سيظهر هنا',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
