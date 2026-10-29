/// ============================================================
/// نموذج الجهاز المكتشف على الشبكة
/// ============================================================
class DiscoveredDevice {
  final String deviceId;
  final String number; // ← جديد: رقم الاتصال (مثل 4500)
  final String name;
  final String ip;
  final int port;
  final List<String> capabilities;
  final DateTime lastSeen;
  final bool isOnline;

  const DiscoveredDevice({
    required this.deviceId,
    required this.number,
    required this.name,
    required this.ip,
    required this.port,
    required this.capabilities,
    required this.lastSeen,
    required this.isOnline,
  });

  DiscoveredDevice copyWith({
    String? deviceId,
    String? number,
    String? name,
    String? ip,
    int? port,
    List<String>? capabilities,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return DiscoveredDevice(
      deviceId: deviceId ?? this.deviceId,
      number: number ?? this.number,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      capabilities: capabilities ?? this.capabilities,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  bool get supportsVideo => capabilities.contains('video');
  bool get supportsVoice => capabilities.contains('voice');

  /// هل الرقم صالح؟
  bool get hasValidNumber => number.isNotEmpty && number != '----';

  @override
  String toString() =>
      'DiscoveredDevice($name, #$number, $ip:$port, online=$isOnline)';
}
