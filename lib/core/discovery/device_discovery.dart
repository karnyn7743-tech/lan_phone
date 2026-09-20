Import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import 'discovered_device.dart';

/// ============================================================
/// خدمة اكتشاف الأجهزة على الشبكة المحلية
/// مع دعم رقم الاتصال (مثل رقم SIM)
/// ============================================================
class DeviceDiscovery extends ChangeNotifier {
  DeviceDiscovery();

  // ============================================
  // === الحالة الداخلية ===
  // ============================================

  String _deviceId = '';
  String get deviceId => _deviceId;

  String _deviceName = '';
  String get deviceName => _deviceName;

  /// رقم الاتصال الخاص بنا (مثل 4500)
  String _deviceNumber = '';
  String get deviceNumber => _deviceNumber;

  String _localIp = '';
  String get localIp => _localIp;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  final Map<String, DiscoveredDevice> _devices = {};
  List<DiscoveredDevice> get devices => _devices.values.toList();

  List<DiscoveredDevice> get onlineDevices =>
      _devices.values.where((d) => d.isOnline).toList();

  /// خريطة عكسية: number → deviceId (للبحث السريع)
  final Map<String, String> _numberToDeviceId = {};

  // ============================================
  // === Sockets و Timers ===
  // ============================================
  RawDatagramSocket? _udpSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _presenceTimer;

  MDnsClient? _mdnsClient;
  StreamSubscription<PtrResourceRecord>? _mdnsSubscription;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  Future<void> start() async {
    if (_isRunning) return;

    try {
      // 1) تحميل/إنشاء الهوية
      await _loadOrCreateIdentity();

      // 2) اكتشاف IP المحلي
      _localIp = await _detectLocalIp();
      debugPrint('[Discovery] Local IP: $_localIp');
      debugPrint('[Discovery] Device: $_deviceName (#$_deviceNumber)');

      // 3) فتح UDP
      await _openUdpSocket();

      // 4) بدء mDNS
      _startMdns();

      // 5) تحميل الأجهزة المخزنة
      await _loadStoredDevices();

      // 6) نبضة أولى
      _sendAnnounce();

      // 7) المؤقتات
      _announceTimer = Timer.periodic(
        const Duration(seconds: AppConstants.announceIntervalSeconds),
        (_) => _sendAnnounce(),
      );

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _cleanupStaleDevices(),
      );

      _presenceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _sendAnnounce(),
      );

      Future.delayed(const Duration(seconds: 30), () {
        _presenceTimer?.cancel();
        _presenceTimer = null;
      });

      _isRunning = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Discovery] Failed to start: $e');
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _presenceTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer = null;
    _presenceTimer = null;

    await _mdnsSubscription?.cancel();
    _mdnsSubscription = null;
    _mdnsClient?.stop();
    _mdnsClient = null;

    try {
      _sendBye();
    } catch (_) {}

    _udpSocket?.close();
    _udpSocket = null;

    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ============================================
  // === الهوية (Identity + Number) ===
  // ============================================

  Future<void> _loadOrCreateIdentity() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) معرّف الجهاز
    var id = prefs.getString(AppConstants.keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(AppConstants.keyDeviceId, id);
    }
    _deviceId = id;

    // 2) اسم الجهاز
    var name = prefs.getString(AppConstants.keyDeviceName);
    if (name == null || name.isEmpty) {
      name = 'LanPhone-${_deviceId.substring(0, 4).toUpperCase()}';
      await prefs.setString(AppConstants.keyDeviceName, name);
    }
    _deviceName = name;

    // 3) رقم الاتصال
    var number = prefs.getString(AppConstants.keyDeviceNumber);
    if (number == null || number.isEmpty) {
      // أول تشغيل — نولّد رقمًا جديدًا
      number = await _generateUniqueNumber();
      await prefs.setString(AppConstants.keyDeviceNumber, number);
      debugPrint('[Discovery] Generated number: $number');
    }
    _deviceNumber = number;
  }

  /// توليد رقم اتصال فريد (4 أرقام)
  Future<String> _generateUniqueNumber() async {
    // 1) اجمع كل الأرقام المستخدمة حاليًا
    final usedNumbers = <String>{};

    // من الأجهزة المكتشفة في الذاكرة
    for (final d in _devices.values) {
      if (d.hasValidNumber) usedNumbers.add(d.number);
    }

    // من قاعدة البيانات
    try {
      final dbNumbers = await DatabaseHelper.instance.getAllUsedNumbers();
      usedNumbers.addAll(dbNumbers);
    } catch (_) {}

    // 2) حاول عدة مرات لتوليد رقم غير مستخدم
    final random = Random.secure();
    for (var i = 0; i < AppConstants.numberGenerationRetries; i++) {
      final candidate = (AppConstants.numberMin +
              random.nextInt(
                AppConstants.numberMax - AppConstants.numberMin + 1,
              ))
          .toString();

      if (!usedNumbers.contains(candidate)) {
        return candidate;
      }
    }

    // 3) إذا فشلنا (نادر جدًا) → استخدم رقمًا مشتقًا من deviceId
    final hash = _deviceId.hashCode.abs();
    final fallback = (AppConstants.numberMin +
            (hash % (AppConstants.numberMax - AppConstants.numberMin + 1)))
        .toString();
    debugPrint('[Discovery] Fallback number: $fallback');
    return fallback;
  }

  /// تحديث اسم الجهاز
  Future<void> updateDeviceName(String newName) async {
    if (newName.trim().isEmpty) return;
    _deviceName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyDeviceName, _deviceName);
    _sendAnnounce();
    notifyListeners();
  }

  /// تحديث رقم الجهاز (من الإعدادات)
  Future<bool> updateDeviceNumber(String newNumber) async {
    if (newNumber.length != 4) return false;
    final parsed = int.tryParse(newNumber);
    if (parsed == null ||
        parsed < AppConstants.numberMin ||
        parsed > AppConstants.numberMax) {
      return false;
    }

    // تحقق: هل الرقم مستخدم من جهاز آخر؟
    final usedByOther = _numberToDeviceId.containsKey(newNumber) &&
        _numberToDeviceId[newNumber] != _deviceId;
    if (usedByOther) {
      debugPrint('[Discovery] Number $newNumber already in use');
      return false;
    }

    try {
      final dbUsed = await DatabaseHelper.instance.isNumberUsedByOther(
        newNumber,
        _deviceId,
      );
      if (dbUsed) return false;
    } catch (_) {}

    _deviceNumber = newNumber;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyDeviceNumber, newNumber);
    _sendAnnounce();
    notifyListeners();
    return true;
  }

  // ============================================
  // === كشف IP المحلي ===
  // ============================================

  Future<String> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('en0')) {
          for (final addr in iface.addresses) {
            if (_isPrivateIp(addr.address)) return addr.address;
          }
        }
      }

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivateIp(addr.address)) return addr.address;
        }
      }

      return '127.0.0.1';
    } catch (e) {
      debugPrint('[Discovery] detectLocalIp error: $e');
      return '127.0.0.1';
    }
  }

  bool _isPrivateIp(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  // ============================================
  // === UDP Socket ===
  // ============================================

  Future<void> _openUdpSocket() async {
    _udpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );

    _udpSocket!.broadcastEnabled = true;
    _udpSocket!.multicastHops = 1;

    _udpSocket!.listen(
      _onUdpEvent,
      onError: (e) => debugPrint('[Discovery] UDP error: $e'),
      onDone: () => debugPrint('[Discovery] UDP closed'),
    );
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _udpSocket?.receive();
    if (datagram == null) return;

    try {
      final text = utf8.decode(datagram.data);
      final data = jsonDecode(text) as Map<String, dynamic>;
      _handleIncoming(data, datagram.address.address);
    } catch (_) {
      // حزمة غير صالحة — تجاهل
    }
  }

  // ============================================
  // === إرسال النبضات ===
  // ============================================

  void _sendAnnounce() {
    _broadcast({
      'type': AppConstants.msgAnnounce,
      'deviceId': _deviceId,
      'number': _deviceNumber, // ← جديد
      'name': _deviceName,
      'ip': _localIp,
      'port': AppConstants.signalingPort,
      'messagePort': AppConstants.messagePort,
      'capabilities': ['text', 'voice', 'video', 'media'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendBye() {
    _broadcast({
      'type': AppConstants.msgBye,
      'deviceId': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _broadcast(Map<String, dynamic> payload) {
    if (_udpSocket == null) return;

    try {
      final data = utf8.encode(jsonEncode(payload));

      _udpSocket!.send(
        data,
        InternetAddress(AppConstants.broadcastAddress),
        AppConstants.discoveryPort,
      );

      _udpSocket!.send(
        data,
        InternetAddress(AppConstants.multicastAddress),
        AppConstants.discoveryPort,
      );
    } catch (e) {
      debugPrint('[Discovery] broadcast error: $e');
    }
  }

  // ============================================
  // === استقبال النبضات ===
  // ============================================

  Future<void> _handleIncoming(
    Map<String, dynamic> data,
    String sourceIp,
  ) async {
    final type = data['type'] as String?;
    final deviceId = data['deviceId'] as String?;
    if (deviceId == null) return;

    // تجاهل نبضاتنا
    if (deviceId == _deviceId) return;

    switch (type) {
      case AppConstants.msgAnnounce:
        await _handleAnnounce(data, sourceIp);
        break;
      case AppConstants.msgBye:
        await _handleBye(deviceId);
        break;
      default:
        break;
    }
  }

  Future<void> _handleAnnounce(
    Map<String, dynamic> data,
    String sourceIp,
  ) async {
    final deviceId = data['deviceId'] as String;
    final name = (data['name'] as String?) ?? 'جهاز غير معروف';
    final number = (data['number'] as String?) ?? '';
    final ip = sourceIp;
    final port = (data['port'] as int?) ?? AppConstants.signalingPort;
    final caps = (data['capabilities'] as List?)?.cast<String>() ?? const [];

    // ============================================
    // === كشف التعارض في الأرقام ===
    // ============================================
    if (number.isNotEmpty && number == _deviceNumber) {
      // جهاز آخر يستخدم نفس رقمنا!
      // القاعدة: مقارنة deviceId نصيًا. الأكبر يُعيد التوليد.
      if (_deviceId.compareTo(deviceId) > 0) {
        debugPrint(
          '[Discovery] Number conflict! We ($_deviceId) regenerate, '
          'peer ($deviceId) keeps $number',
        );
        // نحن الأكبر → نُعيد التوليد
        await _regenerateNumber();
        // لا نحفظ الجهاز الآخر برقمنا القديم الآن — سنستقبل نبضته القادمة
      } else {
        debugPrint(
          '[Discovery] Number conflict! Peer ($deviceId) should regenerate, '
          'we keep $number',
        );
      }
    }

    final isNew = !_devices.containsKey(deviceId);

    // احفظ الخريطة العكسية
    if (number.isNotEmpty) {
      _numberToDeviceId[number] = deviceId;
    }

    final device = DiscoveredDevice(
      deviceId: deviceId,
      number: number,
      name: name,
      ip: ip,
      port: port,
      capabilities: caps,
      lastSeen: DateTime.now(),
      isOnline: true,
    );

    _devices[deviceId] = device;

    // حفظ في قاعدة البيانات
    await DatabaseHelper.instance.upsertDevice({
      'device_id': deviceId,
      'number': number,
      'name': name,
      'ip_address': ip,
      'port': port,
      'capabilities': jsonEncode(caps),
      'last_seen': DateTime.now().millisecondsSinceEpoch,
      'is_favorite': 0,
      'is_blocked': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    if (isNew) {
      debugPrint('[Discovery] New device: $name (#$number) @ $ip');
    }

    notifyListeners();
  }

  Future<void> _handleBye(String deviceId) async {
    if (_devices.containsKey(deviceId)) {
      final old = _devices[deviceId]!;
      // احذف الرقم من الخريطة العكسية
      if (old.hasValidNumber) {
        _numberToDeviceId.remove(old.number);
      }
      _devices[deviceId] = old.copyWith(isOnline: false);
      notifyListeners();
    }
  }

  /// إعادة توليد الرقم عند التعارض
  Future<void> _regenerateNumber() async {
    // احذف رقمنا القديم من الخريطة العكسية
    _numberToDeviceId.remove(_deviceNumber);

    // ولّد رقمًا جديدًا
    final newNumber = await _generateUniqueNumber();
    _deviceNumber = newNumber;

    // احفظ
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyDeviceNumber, newNumber);

    debugPrint('[Discovery] New number: $newNumber');

    // بثّ النبضة فورًا بالرقم الجديد
    _sendAnnounce();
    notifyListeners();
  }

  // ============================================
  // === تنظيف الأجهزة المنقطعة ===
  // ============================================

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool changed = false;

    for (final entry in _devices.entries.toList()) {
      final d = entry.value;
      final diff = now.difference(d.lastSeen).inSeconds;

      if (d.isOnline && diff > AppConstants.deviceTimeoutSeconds) {
        _devices[entry.key] = d.copyWith(isOnline: false);
        changed = true;
        debugPrint('[Discovery] Device offline: ${d.name}');
      }
    }

    if (changed) notifyListeners();
  }

  // ============================================
  // === تحميل الأجهزة المخزّنة ===
  // ============================================

  Future<void> _loadStoredDevices() async {
    try {
      final rows = await DatabaseHelper.instance.getAllDevices();
      for (final row in rows) {
        final id = row['device_id'] as String;
        if (id == _deviceId) continue;

        final number = (row['number'] as String?) ?? '';

        _devices[id] = DiscoveredDevice(
          deviceId: id,
          number: number,
          name: row['name'] as String,
          ip: row['ip_address'] as String,
          port: row['port'] as int,
          capabilities: _parseCaps(row['capabilities']),
          lastSeen: DateTime.fromMillisecondsSinceEpoch(
            row['last_seen'] as int,
          ),
          isOnline: false,
        );

        // احفظ في الخريطة العكسية
        if (number.isNotEmpty) {
          _numberToDeviceId[number] = id;
        }
      }
      debugPrint('[Discovery] Loaded ${_devices.length} stored devices');
      notifyListeners();
    } catch (e) {
      debugPrint('[Discovery] loadStoredDevices error: $e');
    }
  }

  List<String> _parseCaps(dynamic raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw as String) as List;
      return decoded.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  // ============================================
  // === mDNS ===
  // ============================================

  void _startMdns() {
    try {
      _mdnsClient = MDnsClient();
      _mdnsClient!.start().then((_) {
        _mdnsSubscription = _mdnsClient!
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(AppConstants.mdnsServiceType),
            )
            .listen((ptr) async {
          debugPrint('[Discovery] mDNS found: ${ptr.domainName}');
          await _resolveMdnsService(ptr.domainName);
        });
      });
    } catch (e) {
      debugPrint('[Discovery] mDNS start error: $e');
    }
  }

  Future<void> _resolveMdnsService(String serviceName) async {
    try {
      await for (final srv in _mdnsClient!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName),
      )) {
        await for (final txt in _mdnsClient!.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(serviceName),
        )) {
          final txtParts = txt.text.split(',');
          String? deviceId;
          for (final part in txtParts) {
            if (part.startsWith('id=')) deviceId = part.substring(3);
          }
          if (deviceId == null || deviceId == _deviceId) return;

          debugPrint(
            '[Discovery] mDNS resolved: $deviceId @ ${srv.target}:${srv.port}',
          );
        }
      }
    } catch (e) {
      debugPrint('[Discovery] resolveMdns error: $e');
    }
  }

  // ============================================
  // === واجهات عامة للاستعلام ===
  // ============================================

  DiscoveredDevice? getDevice(String deviceId) => _devices[deviceId];

  /// البحث عن جهاز بالرقم
  DiscoveredDevice? getDeviceByNumber(String number) {
    final deviceId = _numberToDeviceId[number];
    if (deviceId == null) return null;
    return _devices[deviceId];
  }

  bool isDeviceOnline(String deviceId) {
    final d = _devices[deviceId];
    return d != null && d.isOnline;
  }

  /// هل الرقم موجود بين الأجهزة المتصلة؟
  bool isNumberOnline(String number) {
    final device = getDeviceByNumber(number);
    return device != null && device.isOnline;
  }

  /// كل الأرقام المستخدمة حاليًا (في الذاكرة)
  Set<String> getUsedNumbers() {
    return _devices.values
        .where((d) => d.hasValidNumber)
        .map((d) => d.number)
        .toSet();
  }

  void refreshNow() {
    _sendAnnounce();
  }

  Future<void> removeDevice(String deviceId) async {
    final device = _devices.remove(deviceId);
    if (device != null && device.hasValidNumber) {
      _numberToDeviceId.remove(device.number);
    }
    await DatabaseHelper.instance.deleteDevice(deviceId);
    notifyListeners();
  }
}
