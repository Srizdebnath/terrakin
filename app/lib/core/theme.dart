import 'package:flutter/material.dart';

/// Colour and type tokens from DESIGN.md sections 3 and 4.
class TK {
  static const ink = Color(0xFF231A2E);
  static const night = Color(0xFF141220);
  static const dusk = Color(0xFF1F1B30);
  static const slate = Color(0xFF3A3452);
  static const paper = Color(0xFFF6EFE2);
  static const paperShade = Color(0xFFE6DBC6);
  static const mist = Color(0xFFB9B3CC);
  static const signal = Color(0xFFFFB547);
  static const danger = Color(0xFFFF5D6C);
  static const loop = Color(0xFF4FD1E8); // Loop Capture trail
  static const drop = Color(0xFFB98CFF); // dead drops

  static TextStyle display(double size, {Color color = paper}) => TextStyle(
        fontFamily: 'Fredoka',
        fontSize: size,
        color: color,
        fontVariations: const [FontVariation('wght', 600)],
        height: 1.1,
      );

  static TextStyle body(double size, {Color color = paper, bool bold = false}) => TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        color: color,
        fontVariations: [FontVariation('wght', bold ? 600 : 400)],
      );

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: night,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: signal,
          onPrimary: ink,
          // Chips and segmented buttons use the secondary roles; keep them amber.
          secondary: signal,
          onSecondary: ink,
          secondaryContainer: signal,
          onSecondaryContainer: ink,
          surface: dusk,
          onSurface: paper,
          error: danger,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: signal,
            foregroundColor: ink,
            minimumSize: const Size(48, 52),
            textStyle: display(18, color: ink),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
}
