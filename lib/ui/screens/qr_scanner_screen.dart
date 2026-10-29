import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/services/qr_service.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة ماسح QR
/// تقرأ رمز QR من جهاز آخر لإضافته فورًا
/// ============================================================
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  // ============================================
  // === المراجع ===
  // ============================================
  late final MobileScannerController _controller;

  // ============================================
  // === الحالة ===
  // ============================================
  bool _isProcessing = false;
  bool _hasScanned = false;
  String? _errorMessage;
  QrDeviceData? _lastScanned;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller.stop();
        break;
      default:
        break;
    }
  }

  // ============================================
  // === معالجة المسح ===
  // ============================================

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _isProcessing = true);

    // اهتزاز خفيف
    HapticFeedback.mediumImpact();

    // ✅ تحقق أولًا: هل هو رمز تسجيل شبكة؟ (غير مخصص لهذا الماسح)
    if (QrService.isNetworkRegistrationQr(raw)) {
      setState(() {
        _errorMessage = 'هذا رمز تسجيل شبكة WiFi\n'
            'مخصص لتطبيق إدارة المشتركين\n'
            'ولا يمكن استخدامه للربط بين الأجهزة';
        _isProcessing = false;
      });
      HapticFeedback.heavyImpact();

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _errorMessage = null);
        }
      });
      return;
    }

    // حلّل QR (كرمز ربط جهاز)
    final data = QrService.decode(raw);

    if (data == null) {
      // QR غير صالح → أظهر خطأ ثم اسمح بإعادة المحاولة
      setState(() {
        _errorMessage = 'هذا الرمز ليس رمز LanPhone صالح';
        _isProcessing = false;
      });
      HapticFeedback.heavyImpact();

      // اسمح بإعادة المحاولة بعد 2 ثانية
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _errorMessage = null);
        }
      });
      return;
    }

    // تحقق: هل هذا جهازنا؟
    final myDeviceId = context.read<DeviceDiscovery>().deviceId;
    if (data.deviceId == myDeviceId) {
      setState(() {
        _errorMessage = 'هذا رمز جهازك — لا يمكن الاقتران بنفسك';
        _isProcessing = false;
      });
      HapticFeedback.heavyImpact();

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _errorMessage = null);
      });
      return;
    }

    // ✅ QR صالح
    _hasScanned = true;
    _lastScanned = data;

    await _showConfirmation(data);
  }

  // ============================================
  // === نافذة التأكيد ===
  // ============================================

  Future<void> _showConfirmation(QrDeviceData data) async {
    await _controller.stop();

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.qr_code_2,
            size: 36,
            color: AppTheme.primaryColor,
          ),
        ),
        title: const Text(
          'إضافة جهاز؟',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogRow('الاسم', data.name),
            const SizedBox(height: 8),
            _dialogRow(
              'الرقم',
              data.number.isEmpty ? '—' : '#${data.number}',
            ),
            const SizedBox(height: 8),
            _dialogRow(
              'IP',
              data.ip.isEmpty ? 'غير معروف' : data.ip,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _addDevice(data);
    } else {
      // المستخدم ألغى → اسمح بالمسح مجددًا
      if (mounted) {
        setState(() {
          _hasScanned = false;
          _isProcessing = false;
          _lastScanned = null;
        });
        await _controller.start();
      }
    }
  }

  Widget _dialogRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ============================================
  // === إضافة الجهاز ===
  // ============================================

  Future<void> _addDevice(QrDeviceData data) async {
    try {
      final discovery = context.read<DeviceDiscovery>();

      // احفظ في قاعدة البيانات
      await DatabaseHelper.instance.upsertDevice({
        'device_id': data.deviceId,
        'number': data.number,
        'name': data.name,
        'ip_address': data.ip,
        'port': data.port,
        'capabilities': jsonEncode(data.capabilities),
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        'is_favorite': 1, // ✅ ضعه في المفضلة
        'is_blocked': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // حدّث الاكتشاف
      discovery.refreshNow();

      if (!mounted) return;

      // اهتزاز نجاح
      HapticFeedback.mediumImpact();

      // أغلق الشاشة وارجع
      Navigator.of(context).pop(data);
    } catch (e) {
      debugPrint('[QRScanner] Add device error: $e');
      if (!mounted) return;

      setState(() {
        _errorMessage = 'تعذّر إضافة الجهاز';
      });
    }
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ماسح QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // تبديل الكاميرا
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'تبديل الكاميرا',
            onPressed: () => _controller.switchCamera(),
          ),
          // كشاف
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, state, __) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            tooltip: 'الكشاف',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ============================================
          // === الكاميرا ===
          // ============================================
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                return _buildCameraError(error);
              },
            ),
          ),

          // ============================================
          // === إطار المسح ===
          // ============================================
          if (_errorMessage == null)
            Positioned.fill(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(),
              ),
            ),

          // ============================================
          // === تعليمات ===
          // ============================================
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: _buildInstruction(),
          ),

          // ============================================
          // === رسالة خطأ ===
          // ============================================
          if (_errorMessage != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.errorColor,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _errorMessage = null);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('حاول مجددًا'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================
  // === عناصر الواجهة ===
  // ============================================

  Widget _buildCameraError(MobileScannerException error) {
    final isPermissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermissionDenied
                  ? Icons.no_photography_outlined
                  : Icons.error_outline,
              color: AppTheme.errorColor,
              size: 72,
            ),
            const SizedBox(height: 20),
            Text(
              isPermissionDenied
                  ? 'نحتاج إذن الكاميرا لمسح الرمز'
                  : 'تعذّر فتح الكاميرا',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isPermissionDenied
                  ? 'اذهب لإعدادات التطبيق وفعّل إذن الكاميرا'
                  : error.errorDetails?.message ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstruction() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isProcessing && !_hasScanned)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(
                Icons.qr_code_scanner,
                color: Colors.white,
                size: 20,
              ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _hasScanned
                    ? 'تم المسح!'
                    : 'وجّه الكاميرا نحو رمز QR',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// === رسم إطار المسح ===
// ============================================================
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // حجم مربع المسح
    final scanSize = size.width * 0.7;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: scanSize,
      height: scanSize,
    );

    // طبقة معتمة حول الإطار
    final overlay = Paint()..color = Colors.black.withOpacity(0.6);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);

    // إطار المسح (خطوط الزوايا فقط)
    final cornerPaint = Paint()
      ..color = AppTheme.primaryColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cornerLength = scanSize * 0.15;
    const radius = 24.0;

    // الزاوية العلوية اليسرى
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + radius + cornerLength)
        ..lineTo(rect.left, rect.top + radius)
        ..arcToPoint(
          Offset(rect.left + radius, rect.top),
          radius: const Radius.circular(radius),
        )
        ..lineTo(rect.left + radius + cornerLength, rect.top),
      cornerPaint,
    );

    // الزاوية العلوية اليمنى
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - radius - cornerLength, rect.top)
        ..lineTo(rect.right - radius, rect.top)
        ..arcToPoint(
          Offset(rect.right, rect.top + radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(rect.right, rect.top + radius + cornerLength),
      cornerPaint,
    );

    // الزاوية السفلية اليمنى
    canvas.drawPath(
      Path()
        ..moveTo(rect.right, rect.bottom - radius - cornerLength)
        ..lineTo(rect.right, rect.bottom - radius)
        ..arcToPoint(
          Offset(rect.right - radius, rect.bottom),
          radius: const Radius.circular(radius),
        )
        ..lineTo(rect.right - radius - cornerLength, rect.bottom),
      cornerPaint,
    );

    // الزاوية السفلية اليسرى
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + radius + cornerLength, rect.bottom)
        ..lineTo(rect.left + radius, rect.bottom)
        ..arcToPoint(
          Offset(rect.left, rect.bottom - radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(rect.left, rect.bottom - radius - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
