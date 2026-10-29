import 'package:flutter/material.dart';

/// ============================================================
/// ثيمات التطبيق (فاتح + داكن)
/// ألوان هادئة مستوحاة من تطبيقات المراسلة الحديثة
/// ============================================================
class AppTheme {
  AppTheme._(); // منع الإنشاء

  // ============================================
  // === الألوان الأساسية ===
  // ============================================
  static const Color primaryColor = Color(0xFF0F7B6C);      // أخضر مزرق هادئ
  static const Color accentColor = Color(0xFF25D366);       // أخضر مراسلة
  static const Color errorColor = Color(0xFFE53935);        // أحمر للمكالمات الفائتة
  static const Color warningColor = Color(0xFFFFA726);      // برتقالي
  static const Color successColor = Color(0xFF43A047);      // أخضر نجاح

  // ============================================
  // === ألوان الوضع الفاتح ===
  // ============================================
  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightDivider = Color(0xFFE5E7EB);
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color lightOutgoingBubble = Color(0xFFDCF8C6);

  // ============================================
  // === ألوان الوضع الداكن ===
  // ============================================
  static const Color darkBackground = Color(0xFF0F1418);
  static const Color darkSurface = Color(0xFF1C2227);
  static const Color darkTextPrimary = Color(0xFFECEFF1);
  static const Color darkTextSecondary = Color(0xFF9AA4AE);
  static const Color darkDivider = Color(0xFF2A3138);
  static const Color darkIncomingBubble = Color(0xFF1F2A30);
  static const Color darkOutgoingBubble = Color(0xFF075E54);

  // ============================================
  // === الوضع الفاتح ===
  // ============================================
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: lightBackground,
        colorScheme: const ColorScheme.light(
          primary: primaryColor,
          secondary: accentColor,
          error: errorColor,
          surface: lightSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: lightTextPrimary,
        ),

        // شريط التطبيق
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),

        // الأزرار
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // حقول الإدخال
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
        ),

        // الفواصل
        dividerTheme: const DividerThemeData(
          color: lightDivider,
          thickness: 1,
          space: 1,
        ),

        // النصوص
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: lightTextPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: lightTextPrimary, fontSize: 14),
          bodySmall: TextStyle(color: lightTextSecondary, fontSize: 12),
          titleLarge: TextStyle(
            color: lightTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          titleMedium: TextStyle(
            color: lightTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),

        // أيقونات
        iconTheme: const IconThemeData(color: lightTextPrimary),
      );

  // ============================================
  // === الوضع الداكن ===
  // ============================================
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          secondary: accentColor,
          error: errorColor,
          surface: darkSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: darkTextPrimary,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: darkSurface,
          foregroundColor: darkTextPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: darkTextPrimary,
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: darkDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: darkDivider,
          thickness: 1,
          space: 1,
        ),

        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: darkTextPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: darkTextPrimary, fontSize: 14),
          bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12),
          titleLarge: TextStyle(
            color: darkTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          titleMedium: TextStyle(
            color: darkTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),

        iconTheme: const IconThemeData(color: darkTextPrimary),
      );
}
