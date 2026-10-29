import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// ============================================================
/// مزوّد الثيم — يتيح تغيير المظهر فوريًا في كل التطبيق
/// ============================================================
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// ✅ القيمة النصية الحالية: 'light' / 'dark' / 'system'
  /// تُستخدم في `settings_screen.dart` لتحديد الاختيار النشط
  String get themeModeString {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(AppConstants.keyThemeMode) ?? 'system';
      _themeMode = _stringToThemeMode(mode);
      notifyListeners();
    } catch (e) {
      debugPrint('[ThemeProvider] load error: $e');
    }
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = _stringToThemeMode(mode);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyThemeMode, mode);
    } catch (e) {
      debugPrint('[ThemeProvider] save error: $e');
    }
  }

  ThemeMode _stringToThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
