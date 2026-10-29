import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../theme/app_theme.dart';
import '../widgets/permission_dialog.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';

/// ============================================================
/// شاشة الاتصال برقم
/// لوحة أرقام مثل الهاتف العادي
/// ============================================================
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  String _input = '';
  String? _errorMessage;

  // ============================================
  // === الإدخال ===
  // ============================================

  void _appendDigit(String digit) {
    if (_input.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _input += digit;
      _errorMessage = null;
    });
  }

  void _deleteDigit() {
    if (_input.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _errorMessage = null;
    });
  }

  void _clearAll() {
    if (_input.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _input = '';
      _errorMessage = null;
    });
  }

  // ============================================
  // === الاتصال ===
  // ============================================

  Future<void> _call({required bool isVideo}) async {
    if (_input.isEmpty) {
      setState(() => _errorMessage = 'أدخل رقمًا للاتصال');
      return;
    }

    // ابحث عن الجهاز بالرقم
    final discovery = context.read<DeviceDiscovery>();
    final device = discovery.getDeviceByNumber(_input);

    if (device == null) {
      setState(() => _errorMessage = 'الرقم $_input غير مسجّل على الشبكة');
      _vibrateError();
      return;
    }

    if (!device.isOnline) {
      setState(() => _errorMessage = 'الجهاز ${device.name} غير متصل الآن');
      _vibrateError();
      return;
    }

    // اطلب الأذونات
    final permissions = isVideo
        ? <ph.Permission>[
            ph.Permission.microphone,
            ph.Permission.camera,
          ]
        : <ph.Permission>[ph.Permission.microphone];

    final granted = await PermissionDialog.ensure(
      context,
      permissions: permissions,
      title: isVideo ? 'الكاميرا والميكروفون' : 'الميكروفون',
      message: isVideo
          ? 'نحتاجهما لإجراء مكالمات الفيديو'
          : 'نحتاج الميكروفون لإجراء المكالمات الصوتية',
      icon: isVideo ? Icons.videocam : Icons.mic,
    );

    if (!granted || !mounted) return;

    // اذهب لشاشة المكالمة
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isVideo
            ? VideoCallScreen(peer: device, isCaller: true)
            : AudioCallScreen(peer: device, isCaller: true),
      ),
    );
  }

  void _vibrateError() {
    HapticFeedback.heavyImpact();
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A1F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('الاتصال برقم'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ============================================
            // === العرض ===
            // ============================================
            Expanded(
              flex: 2,
              child: _buildDisplay(),
            ),

            // ============================================
            // === لوحة الأرقام ===
            // ============================================
            Expanded(
              flex: 5,
              child: _buildKeypad(),
            ),

            // ============================================
            // === أزرار الاتصال ===
            // ============================================
            _buildCallButtons(),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === منطقة العرض ===
  // ============================================

  Widget _buildDisplay() {
    final discovery = context.watch<DeviceDiscovery>();
    final device = _input.isNotEmpty
        ? discovery.getDeviceByNumber(_input)
        : null;

    final isComplete = _input.length == 4;
    final knownNumber = device != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // الرقم المُدخل
          Text(
            _input.isEmpty ? 'أدخل رقمًا' : _input,
            style: TextStyle(
              fontSize: _input.isEmpty ? 28 : 48,
              fontWeight: FontWeight.w300,
              letterSpacing: _input.isEmpty ? 0 : 8,
              color: _input.isEmpty
                  ? Colors.white.withOpacity(0.35)
                  : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // معلومات الجهاز (إن وُجد)
          if (isComplete && knownNumber)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.isOnline
                        ? AppTheme.successColor
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  device.isOnline
                      ? '${device.name} • متصل'
                      : '${device.name} • غير متصل',
                  style: TextStyle(
                    fontSize: 15,
                    color: device.isOnline
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            )
          else if (isComplete && !knownNumber)
            Text(
              'لا يوجد جهاز بهذا الرقم',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            )
          else if (_input.isNotEmpty)
            Text(
              '${_input.length}/4',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.4),
              ),
            ),

          // رسالة الخطأ
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppTheme.errorColor,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================
  // === لوحة الأرقام ===
  // ============================================

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          _buildRow(['clear', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map(_buildKey).toList(),
    );
  }

  Widget _buildKey(String value) {
    // زر الحذف
    if (value == 'back') {
      return _DialKey(
        onTap: _deleteDigit,
        onLongPress: _clearAll,
        child: Icon(
          Icons.backspace_outlined,
          color: _input.isEmpty
              ? Colors.white.withOpacity(0.3)
              : Colors.white,
          size: 26,
        ),
      );
    }

    // زر المسح
    if (value == 'clear') {
      return _DialKey(
        onTap: _clearAll,
        child: Icon(
          Icons.clear,
          color: _input.isEmpty
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.75),
          size: 26,
        ),
      );
    }

    // أرقام عادية
    final letters = _keyLetters(value);
    return _DialKey(
      onTap: () => _appendDigit(value),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          if (letters.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              letters,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.55),
                letterSpacing: 1.5,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _keyLetters(String digit) {
    switch (digit) {
      case '2':
        return 'ABC';
      case '3':
        return 'DEF';
      case '4':
        return 'GHI';
      case '5':
        return 'JKL';
      case '6':
        return 'MNO';
      case '7':
        return 'PQRS';
      case '8':
        return 'TUV';
      case '9':
        return 'WXYZ';
      default:
        return '';
    }
  }

  // ============================================
  // === أزرار الاتصال ===
  // ============================================

  Widget _buildCallButtons() {
    final discovery = context.watch<DeviceDiscovery>();
    final device = _input.isNotEmpty
        ? discovery.getDeviceByNumber(_input)
        : null;
    final canCall = device != null && device.isOnline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // زر الفيديو
          _CallActionButton(
            icon: Icons.videocam,
            label: 'فيديو',
            color: AppTheme.primaryColor,
            enabled: canCall,
            onTap: () => _call(isVideo: true),
          ),

          // زر الصوت
          _CallActionButton(
            icon: Icons.call,
            label: 'اتصال',
            color: AppTheme.successColor,
            enabled: canCall,
            onTap: () => _call(isVideo: false),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === زر لوحة الأرقام ===
// ============================================================
class _DialKey extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _DialKey({
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

// ============================================================
// === زر إجراء مكالمة ===
// ============================================================
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: enabled ? color : color.withOpacity(0.3),
          shape: const CircleBorder(),
          elevation: enabled ? 4 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(
                icon,
                size: 30,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: enabled
                ? Colors.white
                : Colors.white.withOpacity(0.4),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
