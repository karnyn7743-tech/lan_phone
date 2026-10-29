import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// فترات القفل التلقائي
/// ============================================================
enum LockDelay {
  immediately,
  after30s,
  after1min,
  after5min,
  never,
}

extension LockDelayExt on LockDelay {
  String get label {
    switch (this) {
      case LockDelay.immediately:
        return 'فورًا';
      case LockDelay.after30s:
        return 'بعد 30 ثانية';
      case LockDelay.after1min:
        return 'بعد دقيقة';
      case LockDelay.after5min:
        return 'بعد 5 دقائق';
      case LockDelay.never:
        return 'أبدًا (قفل يدوي فقط)';
    }
  }

  String get description {
    switch (this) {
      case LockDelay.immediately:
        return 'يُقفل التطبيق عند مغادرته فورًا';
      case LockDelay.after30s:
        return 'يُقفل بعد 30 ثانية من مغادرته';
      case LockDelay.after1min:
        return 'يُقفل بعد دقيقة من مغادرته';
      case LockDelay.after5min:
        return 'يُقفل بعد 5 دقائق من مغادرته';
      case LockDelay.never:
        return 'يُقفل فقط عند إعادة التشغيل';
    }
  }

  Duration? get duration {
    switch (this) {
      case LockDelay.immediately:
        return Duration.zero;
      case LockDelay.after30s:
        return const Duration(seconds: 30);
      case LockDelay.after1min:
        return const Duration(minutes: 1);
      case LockDelay.after5min:
        return const Duration(minutes: 5);
      case LockDelay.never:
        return null;
    }
  }

  String get storageKey {
    switch (this) {
      case LockDelay.immediately:
        return 'immediately';
      case LockDelay.after30s:
        return 'after30s';
      case LockDelay.after1min:
        return 'after1min';
      case LockDelay.after5min:
        return 'after5min';
      case LockDelay.never:
        return 'never';
    }
  }
}

/// ============================================================
/// خدمة قفل التطبيق بالبصمة
/// ============================================================
class LockService extends ChangeNotifier with WidgetsBindingObserver {
  LockService() {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  // ============================================
  // === المفاتيح ===
  // ============================================
  static const String _keyEnabled = 'lock_enabled';
  static const String _keyDelay = 'lock_delay';

  // ============================================
  // === المراجع ===
  // ============================================
  final LocalAuthentication _auth = LocalAuthentication();

  // ============================================
  // === الحالة ===
  // ============================================
  bool _enabled = false;
  bool get enabled => _enabled;

  bool _isLocked = false;
  bool get isLocked => _isLocked;

  bool _isAuthenticating = false;
  bool get isAuthenticating => _isAuthenticating;

  LockDelay _delay = LockDelay.immediately;
  LockDelay get delay => _delay;

  bool _available = false;
  bool get available => _available;

  bool _canCheckBiometrics = false;
  bool get canCheckBiometrics => _canCheckBiometrics;

  List<BiometricType> _biometricTypes = [];
  List<BiometricType> get biometricTypes => _biometricTypes;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _backgroundedAt;
  bool _isFirstLaunch = true;

  // ============================================
  // === التهيئة ===
  // ============================================

  Future<void> _load() async {
    try {
      await _checkAvailability();

      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_keyEnabled) ?? false;

      final delayKey = prefs.getString(_keyDelay) ?? 'immediately';
      _delay = _fromString(delayKey);

      if (_enabled) {
        _isLocked = true;
      }

      debugPrint(
        '[Lock] Loaded: enabled=$_enabled, delay=${_delay.label}, '
        'available=$_available',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('[Lock] load error: $e');
    }
  }

  Future<void> _checkAvailability() async {
    try {
      _available = await _auth.isDeviceSupported();
      _canCheckBiometrics = await _auth.canCheckBiometrics;

      if (_available) {
        _biometricTypes = await _auth.getAvailableBiometrics();
      }

      debugPrint(
        '[Lock] Device supported: $_available, '
        'Biometrics: $_canCheckBiometrics, '
        'Types: $_biometricTypes',
      );
    } catch (e) {
      debugPrint('[Lock] checkAvailability error: $e');
      _available = false;
      _canCheckBiometrics = false;
    }
  }

  // ============================================
  // === التعديل ===
  // ============================================

  Future<bool> setEnabled(bool value) async {
    if (value) {
      // اطلب مصادقة لتأكيد التفعيل
      final ok = await _authenticate(
        reason: 'تأكيد تفعيل قفل التطبيق',
      );
      if (!ok) return false;
    }

    _enabled = value;

    // عند التفعيل → ابقَ غير مقفل مؤقتًا
    if (value) {
      _isLocked = false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, value);
    } catch (e) {
      debugPrint('[Lock] setEnabled error: $e');
    }

    notifyListeners();
    return true;
  }

  Future<void> setDelay(LockDelay delay) async {
    _delay = delay;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDelay, delay.storageKey);
    } catch (e) {
      debugPrint('[Lock] setDelay error: $e');
    }
    notifyListeners();
  }

  // ============================================
  // === القفل / الفتح ===
  // ============================================

  void lock() {
    if (!_enabled) return;
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }

  // ============================================
  // === المصادقة العامة ===
  // ============================================

  Future<bool> authenticate() async {
    // ✅ منع التشغيل المتزامن
    if (_isAuthenticating) {
      debugPrint('[Lock] authenticate: already in progress');
      return false;
    }

    // ✅ مسح أي خطأ سابق قبل البدء
    _lastError = null;
    notifyListeners();

    final ok = await _authenticate(
      reason: 'افتح LanPhone للمتابعة',
    );

    if (ok) {
      _isLocked = false;
      _lastError = null;
      debugPrint('[Lock] Unlocked successfully');
    } else {
      debugPrint('[Lock] Unlock failed: $_lastError');
    }

    notifyListeners();
    return ok;
  }

  // ============================================
  // === المصادقة الداخلية ===
  // ============================================

  Future<bool> _authenticate({required String reason}) async {
    if (_isAuthenticating) {
      debugPrint('[Lock] _authenticate: busy');
      return false;
    }

    if (!_available) {
      _lastError = 'البصمة غير متوفرة على هذا الجهاز';
      notifyListeners();
      return false;
    }

    _isAuthenticating = true;
    _lastError = null;
    notifyListeners();

    bool result = false;
    String? errorMsg;

    try {
      result = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // ✅ السماح بـ PIN/Pattern/Password كبديل
          biometricOnly: false,
          // ✅ مهم: لا تحتفظ بالجلسة (السبب الأساسي للمشكلة)
          stickyAuth: false,
          // ✅ لا نعتمد على حوارات النظام
          useErrorDialogs: false,
          // ✅ معاملة حساسة → أمان أعلى
          sensitiveTransaction: true,
        ),
      );

      debugPrint('[Lock] _authenticate result: $result');
    } on PlatformException catch (e) {
      debugPrint('[Lock] PlatformException: ${e.code} - ${e.message}');
      errorMsg = _parseError(e);
    } catch (e) {
      debugPrint('[Lock] authenticate error: $e');
      errorMsg = 'حدث خطأ غير متوقع';
    } finally {
      _isAuthenticating = false;

      if (errorMsg != null) {
        _lastError = errorMsg;
      } else if (!result) {
        _lastError = 'تم إلغاء التحقق أو فشل';
      }

      notifyListeners();
    }

    return result;
  }

  // ============================================
  // === تحليل أخطاء local_auth ===
  // ============================================

  String _parseError(PlatformException e) {
    switch (e.code) {
      case auth_error.notAvailable:
        return 'البصمة غير متوفرة على هذا الجهاز';
      case auth_error.notEnrolled:
        return 'لا توجد بصمات مسجّلة. أضف بصمة من إعدادات النظام.';
      case auth_error.lockedOut:
        return 'محاولات كثيرة خاطئة. انتظر قليلًا ثم حاول مجددًا.';
      case auth_error.permanentlyLockedOut:
        return 'تم قفل البصمة نهائيًا. افتح ببصمة الجهاز أو أعد تسجيلها.';
      case auth_error.passcodeNotSet:
        return 'لا يوجد قفل شاشة. يجب تفعيل بصمة أو رمز على الجهاز.';
      case auth_error.otherOperatingSystem:
        return 'خطأ في النظام. أعد تشغيل التطبيق.';
      default:
        return 'تعذّر التحقق (${e.code})';
    }
  }

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        if (_enabled) {
          _backgroundedAt = DateTime.now();
          _isFirstLaunch = false;
        }
        break;

      case AppLifecycleState.resumed:
        // ✅ مهلة صغيرة قبل القفل التلقائي
        Future.delayed(const Duration(milliseconds: 100), () {
          _checkLockOnResume();
        });
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _checkLockOnResume() {
    if (!_enabled) return;
    if (_isLocked) return;
    if (_isFirstLaunch) return;
    if (_backgroundedAt == null) return;

    final delayDuration = _delay.duration;

    if (delayDuration == null) {
      _backgroundedAt = null;
      return;
    }

    final elapsed = DateTime.now().difference(_backgroundedAt!);

    if (elapsed >= delayDuration) {
      _isLocked = true;
      debugPrint('[Lock] Auto-locked (elapsed: ${elapsed.inSeconds}s)');
      notifyListeners();
    }

    _backgroundedAt = null;
  }

  // ============================================
  // === أدوات ===
  // ============================================

  LockDelay _fromString(String s) {
    switch (s) {
      case 'after30s':
        return LockDelay.after30s;
      case 'after1min':
        return LockDelay.after1min;
      case 'after5min':
        return LockDelay.after5min;
      case 'never':
        return LockDelay.never;
      default:
        return LockDelay.immediately;
    }
  }

  String get biometricDescription {
    if (!_available) return 'البصمة غير متوفرة';
    if (_biometricTypes.isEmpty) return 'لم يتم تسجيل بصمات';
    if (_biometricTypes.contains(BiometricType.face)) {
      return 'التعرّف على الوجه';
    }
    if (_biometricTypes.contains(BiometricType.fingerprint)) {
      return 'بصمة الإصبع';
    }
    if (_biometricTypes.contains(BiometricType.iris)) {
      return 'بصمة القزحية';
    }
    return 'المصادقة الحيوية';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
