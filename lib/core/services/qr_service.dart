import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../discovery/discovered_device.dart';

/// ============================================================
/// خدمة ترميز وفك ترميز بيانات QR
/// تدعم نوعين من الرموز:
///   1) peer_link   — للربط بجهاز آخر يستخدم LanPhone
///   2) network_registration — لتسجيل الجهاز في شبكة WiFi
///                              (يقرأه تطبيق إدارة المشتركين)
/// ============================================================
class QrService {
  QrService._();

  /// إصدار صيغة QR للربط بين الأجهزة
  static const int _formatVersion = 1;

  /// بادئة رمز تسجيل المشترك في شبكة الواي فاي
  static const String networkPrefix = 'LANPHONE_CLIENT_ID:';

  // ============================================
  // === 1) QR للربط بجهاز آخر (الموجود) ===
  // ============================================

  /// تحويل معلومات الجهاز إلى نص JSON للـ QR
  /// (يُقرأ من قبل جهاز آخر يستخدم نفس التطبيق)
  static String encode({
    required String deviceId,
    required String number,
    required String name,
    required String ip,
    required int port,
    List<String> capabilities = const [
      'text',
      'voice',
      'video',
      'media',
    ],
  }) {
    final data = {
      'v': _formatVersion,
      'id': deviceId,
      'n': number,
      'name': name,
      'ip': ip,
      'port': port,
      'caps': capabilities,
    };

    return jsonEncode(data);
  }

  // ============================================
  // === 2) QR لتسجيل الجهاز في شبكة WiFi (جديد) ===
  // ============================================

  /// توليد رمز QR بصيغة تطبيق إدارة المشتركين
  ///
  /// الصيغة المُخرجة:
  /// ```
  /// LANPHONE_CLIENT_ID:{"name":"...","deviceId":"...","macAddress":"...","phone":"..."}
  /// ```
  static String encodeNetworkRegistration({
    required String fullName,
    required String deviceId,
    required String macAddress,
    String? phone,
  }) {
    final payloadMap = {
      'name': fullName.trim(),
      'deviceId': deviceId.trim(),
      'macAddress': macAddress.trim().toUpperCase(),
      'phone': phone?.trim() ?? '',
    };

    return '$networkPrefix${jsonEncode(payloadMap)}';
  }

  // ============================================
  // === فك الترميز (قراءة QR) ===
  // ============================================

  /// تحليل نص QR إلى نموذج جهاز (لنوع peer_link فقط)
  /// يُرجع `null` إذا كان النص غير صالح أو من نوع آخر
  static QrDeviceData? decode(String raw) {
    try {
      final trimmed = raw.trim();

      // إذا كان رمز تسجيل شبكة، ارفضه (ليس لهذا التطبيق)
      if (trimmed.startsWith(networkPrefix)) {
        debugPrint('[QR] This is a network-registration QR — not for peer link');
        return null;
      }

      // يجب أن يبدأ بـ { (JSON)
      if (!trimmed.startsWith('{')) {
        debugPrint('[QR] Not a LanPhone peer QR');
        return null;
      }

      final Map<String, dynamic> data =
          jsonDecode(trimmed) as Map<String, dynamic>;

      // تحقق من الإصدار
      final version = data['v'] as int?;
      if (version == null || version > _formatVersion) {
        debugPrint('[QR] Unsupported version: $version');
        return null;
      }

      // تحقق من الحقول المطلوبة
      final deviceId = data['id'] as String?;
      final number = data['n'] as String?;
      final name = data['name'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        debugPrint('[QR] Missing deviceId');
        return null;
      }

      if (name == null || name.isEmpty) {
        debugPrint('[QR] Missing name');
        return null;
      }

      final ip = data['ip'] as String? ?? '';
      final port = (data['port'] as num?)?.toInt() ??
          AppConstants.signalingPort;
      final caps = (data['caps'] as List?)?.cast<String>() ??
          const ['text', 'voice', 'video', 'media'];

      return QrDeviceData(
        deviceId: deviceId,
        number: number ?? '',
        name: name,
        ip: ip,
        port: port,
        capabilities: caps,
      );
    } catch (e) {
      debugPrint('[QR] Decode error: $e');
      return null;
    }
  }

  /// فك ترميز رمز تسجيل شبكة
  /// (قد يُستخدم لو أردت مستقبلًا التأكد من الرموز المولّدة)
  static NetworkRegistrationData? decodeNetworkRegistration(String raw) {
    try {
      final trimmed = raw.trim();
      if (!trimmed.startsWith(networkPrefix)) return null;

      final jsonStr = trimmed.substring(networkPrefix.length);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      return NetworkRegistrationData(
        fullName: (data['name'] as String?) ?? '',
        deviceId: (data['deviceId'] as String?) ?? '',
        macAddress: (data['macAddress'] as String?) ?? '',
        phone: (data['phone'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[QR] decodeNetworkRegistration error: $e');
      return null;
    }
  }

  // ============================================
  // === التحقق من الصلاحية ===
  // ============================================

  /// هل هذا النص QR صالح للربط بجهاز آخر؟
  static bool isValidPeerQr(String raw) {
    return decode(raw) != null;
  }

  /// هل هذا النص QR لتسجيل شبكة؟
  static bool isNetworkRegistrationQr(String raw) {
    return raw.trim().startsWith(networkPrefix);
  }
}

// ============================================================
// === نموذج البيانات المُستخرجة من QR (peer_link) ===
// ============================================================
class QrDeviceData {
  final String deviceId;
  final String number;
  final String name;
  final String ip;
  final int port;
  final List<String> capabilities;

  const QrDeviceData({
    required this.deviceId,
    required this.number,
    required this.name,
    required this.ip,
    required this.port,
    required this.capabilities,
  });

  /// تحويل إلى `DiscoveredDevice`
  DiscoveredDevice toDiscoveredDevice({bool isOnline = false}) {
    return DiscoveredDevice(
      deviceId: deviceId,
      number: number,
      name: name,
      ip: ip,
      port: port,
      capabilities: capabilities,
      lastSeen: DateTime.now(),
      isOnline: isOnline,
    );
  }

  @override
  String toString() =>
      'QrDeviceData($name, #$number, $ip:$port)';
}

// ============================================================
// === نموذج بيانات تسجيل الشبكة (network_registration) ===
// ============================================================
class NetworkRegistrationData {
  final String fullName;
  final String deviceId;
  final String macAddress;
  final String phone;

  const NetworkRegistrationData({
    required this.fullName,
    required this.deviceId,
    required this.macAddress,
    required this.phone,
  });

  @override
  String toString() =>
      'NetworkRegistrationData($fullName, $deviceId, $macAddress, $phone)';
}
