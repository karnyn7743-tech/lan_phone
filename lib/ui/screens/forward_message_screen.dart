import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/messaging/message_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة توجيه رسالة إلى جهاز أو أكثر
/// ============================================================
class ForwardMessageScreen extends StatefulWidget {
  /// الرسالة المراد توجيهها
  final Map<String, dynamic> message;

  const ForwardMessageScreen({
    super.key,
    required this.message,
  });

  @override
  State<ForwardMessageScreen> createState() =>
      _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  final Set<String> _selectedDeviceIds = {};
  bool _isSending = false;

  // ============================================
  // === الإرسال ===
  // ============================================

  Future<void> _forward() async {
    if (_selectedDeviceIds.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final messageService = context.read<MessageService>();

      final type = widget.message['type'] as String?;
      final body = widget.message['body'] as String? ?? '';
      final filePath = widget.message['file_path'] as String?;
      final fileName = widget.message['file_name'] as String?;

      int successCount = 0;
      int failCount = 0;

      for (final deviceId in _selectedDeviceIds) {
        try {
          MessageResult result;

          if (type == AppConstants.mediaText) {
            // رسالة نصية
            result = await messageService.sendText(
              peerDeviceId: deviceId,
              body: body,
            );
          } else {
            // وسائط (صورة، فيديو، صوت، ملف)
            if (filePath == null || !File(filePath).existsSync()) {
              failCount++;
              continue;
            }
            result = await messageService.sendMedia(
              peerDeviceId: deviceId,
              filePath: filePath,
              mediaType: type ?? AppConstants.mediaFile,
              caption: body.isEmpty ? null : body,
            );
          }

          if (result.ok) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          debugPrint('[Forward] send to $deviceId error: $e');
          failCount++;
        }
      }

      if (!mounted) return;

      HapticFeedback.mediumImpact();

      Navigator.of(context).pop(
        ForwardResult(
          successCount: successCount,
          failCount: failCount,
        ),
      );
    } catch (e) {
      debugPrint('[Forward] error: $e');
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر التوجيه'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // ============================================
  // === التبديل ===
  // ============================================

  void _toggleDevice(String deviceId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedDeviceIds.contains(deviceId)) {
        _selectedDeviceIds.remove(deviceId);
      } else {
        _selectedDeviceIds.add(deviceId);
      }
    });
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final discovery = context.watch<DeviceDiscovery>();
    final messageService = context.watch<MessageService>();

    // الأجهزة غير المحظورة
    final devices = discovery.devices
        .where((d) => !messageService.blockedDeviceIds.contains(d.deviceId))
        .toList();

    // رتب: المتصلة أولًا، ثم الأحدث ظهورًا
    devices.sort((a, b) {
      if (a.isOnline != b.isOnline) {
        return a.isOnline ? -1 : 1;
      }
      return b.lastSeen.compareTo(a.lastSeen);
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _selectedDeviceIds.isEmpty
              ? 'توجيه إلى'
              : 'توجيه إلى (${_selectedDeviceIds.length})',
        ),
      ),
      body: Column(
        children: [
          // ============================================
          // === معاينة الرسالة ===
          // ============================================
          _buildMessagePreview(isDark),

          // ============================================
          // === قائمة الأجهزة ===
          // ============================================
          Expanded(
            child: devices.isEmpty
                ? _buildEmpty(isDark)
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark
                          ? AppTheme.darkDivider
                          : AppTheme.lightDivider,
                    ),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isSelected =
                          _selectedDeviceIds.contains(device.deviceId);
                      return _DeviceRow(
                        device: device,
                        isSelected: isSelected,
                        onTap: () => _toggleDevice(device.deviceId),
                      );
                    },
                  ),
          ),
        ],
      ),
      // ============================================
      // === زر الإرسال العائم ===
      // ============================================
      floatingActionButton: _selectedDeviceIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSending ? null : _forward,
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isSending
                    ? 'جارٍ الإرسال...'
                    : 'إرسال إلى ${_selectedDeviceIds.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  // ============================================
  // === معاينة الرسالة ===
  // ============================================

  Widget _buildMessagePreview(bool isDark) {
    final type = widget.message['type'] as String?;
    final body = widget.message['body'] as String? ?? '';
    final fileName = widget.message['file_name'] as String?;
    final filePath = widget.message['file_path'] as String?;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.forward,
                      size: 12,
                      color: AppTheme.primaryColor,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'معاينة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // أيقونة النوع
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForType(type),
                  color: AppTheme.primaryColor,
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
                      _previewTitle(type, fileName),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // صورة مصغرة
              if (type == AppConstants.mediaImage &&
                  filePath != null &&
                  File(filePath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(filePath),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case AppConstants.mediaText:
        return Icons.chat_bubble_outline;
      case AppConstants.mediaImage:
        return Icons.image_outlined;
      case AppConstants.mediaVideo:
        return Icons.videocam_outlined;
      case AppConstants.mediaAudio:
        return Icons.mic_none;
      case AppConstants.mediaFile:
        return Icons.insert_drive_file_outlined;
      default:
        return Icons.attach_file;
    }
  }

  String _previewTitle(String? type, String? fileName) {
    switch (type) {
      case AppConstants.mediaText:
        return 'رسالة نصية';
      case AppConstants.mediaImage:
        return 'صورة';
      case AppConstants.mediaVideo:
        return 'فيديو';
      case AppConstants.mediaAudio:
        return 'مقطع صوتي';
      case AppConstants.mediaFile:
        return fileName ?? 'ملف';
      default:
        return 'رسالة';
    }
  }

  // ============================================
  // === حالة فارغة ===
  // ============================================

  Widget _buildEmpty(bool isDark) {
    final textColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: 64,
              color: textColor,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد أجهزة',
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
              'لم يتم العثور على أجهزة غير محظورة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// === صف جهاز للاختيار ===
// ============================================================
class _DeviceRow extends StatelessWidget {
  final DiscoveredDevice device;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? AppTheme.primaryColor.withOpacity(0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.08)
              : (isDark ? AppTheme.darkSurface : Colors.white),
          child: Row(
            children: [
              // الأفاتار
              Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: device.isOnline
                            ? [
                                AppTheme.primaryColor,
                                AppTheme.primaryColor.withOpacity(0.75),
                              ]
                            : [
                                Colors.grey.shade400,
                                Colors.grey.shade600,
                              ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      device.name.isNotEmpty
                          ? device.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: device.isOnline
                            ? AppTheme.successColor
                            : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkSurface
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 14),

              // الاسم والرقم
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (device.hasValidNumber) ...[
                          Text(
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
                          const SizedBox(width: 8),
                        ],
                        Text(
                          device.isOnline ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 12,
                            color: device.isOnline
                                ? AppTheme.successColor
                                : (isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // مربع الاختيار
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isDark
                            ? AppTheme.darkTextSecondary
                            : Colors.grey.shade400),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// === نموذج النتيجة ===
// ============================================================
class ForwardResult {
  final int successCount;
  final int failCount;

  const ForwardResult({
    required this.successCount,
    required this.failCount,
  });

  bool get allSucceeded => failCount == 0 && successCount > 0;
  bool get allFailed => successCount == 0 && failCount > 0;
  bool get partial =>
      successCount > 0 && failCount > 0;
}
