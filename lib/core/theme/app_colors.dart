import 'package:material_ui/material_ui.dart';

abstract final class AppColors {
  // Brand: purple and blue.
  static const purple = Color(0xFF6A3DE8);
  static const blue = Color(0xFF2563EB);
  static const background = Color(0xFFF6F5FB);

  static const brandGradient = LinearGradient(
    colors: [purple, blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Attendance status colours (used from Phase 5). Kept distinct from the
  // brand colours so a status is never mistaken for a button or highlight.
  static const present = Color(0xFF2E7D32);
  static const absent = Color(0xFFC62828);
  static const halfDay = Color(0xFFEF6C00);
  static const leave = Color(0xFF00838F);
  static const late = Color(0xFFF9A825);
}
