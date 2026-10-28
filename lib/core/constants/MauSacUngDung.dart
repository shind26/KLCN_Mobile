import 'package:flutter/material.dart';

/// Bảng màu tập trung toàn ứng dụng Nhà Trọ Kiêu Giang
class AppColors {
  AppColors._(); // Không cho khởi tạo

  // === PRIMARY BRAND ===
  static const Color primary = Color(0xFF09638E); // Xanh dương chủ đạo
  static const Color primaryDark = Color(0xFF145D85); // Xanh sẫm (splash top)
  static const Color primaryMid = Color(0xFF2276A3); // Cyan blue
  static const Color primaryLight = Color(0xFF4C98BD); // Ocean blue
  static const Color primaryPale = Color(
    0xFF6FB6D7,
  ); // Teal sáng (splash bottom)

  // === BACKGROUNDS ===
  static const Color background = Color(0xFFF4F8FA); // Nền app
  static const Color surface = Colors.white; // Nền card/section
  static const Color surfaceAlt = Color(0xFFF8FAFC); // Nền input/box

  // === ACCENT TONES ===
  static const Color accentBlue = Color(0xFFEBF5FA); // Nền nhẹ xanh
  static const Color accentBlueBorder = Color(0xFFBAE6FD);
  static const Color accentGreen = Color(0xFFDCFCE7);
  static const Color accentAmber = Color(0xFFFEF3C7);

  // === STATUS ===
  static const Color success = Color(0xFF16A34A); // Xanh lá (trạng thái OK)
  static const Color warning = Color(0xFFD97706); // Vàng cam
  static const Color info = Color(0xFF0284C7); // Xanh info badge
  static const Color star = Color(0xFFF59E0B); // Vàng sao

  // === TEXT ===
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textPlaceholder = Color(0xFF94A3B8);

  // === BORDER / DIVIDER ===
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFCBD5E1);

  // === SPLASH GRADIENT STOPS ===
  static const List<Color> splashGradient = [
    primaryDark,
    primaryMid,
    primaryLight,
    primaryPale,
  ];
}
