import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/permission_service.dart';

/// ============================================================
/// حوار موحّد لطلب الأذونات
/// ============================================================
class PermissionDialog {
  PermissionDialog._();

  /// يعرض الحوار المناسب حسب حالة الإذن
  /// يُرجع true إذا مُنح الإذن
  static Future<bool> ensure(
    BuildContext context, {
    required List<Permission> permissions,
    required String title,
    required String message,
    required IconData icon,
  }) async {
    final result = await PermissionService.requestWithGuidance(
      permissions,
      message,
    );

    if (result.isOk) return true;

    if (!context.mounted) return false;

    if (result.shouldOpenSettings) {
      // المستخدم رفض نهائيًا → نعرض حوارًا يفتح الإعدادات
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(icon, size: 40, color: Colors.orange),
          title: Text(title),
          content: Text(
            '$message\n\n'
            'تم رفض الإذن. لتفعيله، افتح إعدادات التطبيق ومنح الإذن يدويًا.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقًا'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      );

      if (open == true) {
        await openAppSettings();
      }
      return false;
    } else {
      // رفض عادي → نُظهر رسالة
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم رفض $title'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }
}
