import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Brand tokens — mirrors the approved prototype exactly.
class Brand {
  static const crimson = Color(0xFFB5121A);
  static const crimsonDeep = Color(0xFF7E0A10);
  static const crimsonTint = Color(0xFFFBEAEA);
  static const gold = Color(0xFFC9A24A);
  static const gold2 = Color(0xFFE8C97A);
  static const ink = Color(0xFF171519);
  static const muted = Color(0xFF625E66);
  static const line = Color(0xFFE6E0D6);
  static const bg = Color(0xFFF6F3EE);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFECE7DF);

  static const blue = Color(0xFF155F8E), blueTint = Color(0xFFE3F0F8);
  static const green = Color(0xFF1E7F4F), greenTint = Color(0xFFE4F3EA);
  static const amber = Color(0xFF8A5A00), amberTint = Color(0xFFFDF3DC);
  static const violet = Color(0xFF5B3E99), violetTint = Color(0xFFEFE9F7);

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFC4161E), Color(0xFF9A0F15), Color(0xFF6E080D)], stops: [0, .55, 1],
  );
  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFC4161E), Color(0xFF8E0D13)],
  );

  // dark theme counterparts
  static const dBg = Color(0xFF131215), dSurface = Color(0xFF1E1D21), dSurface2 = Color(0xFF2A282E);
  static const dFg = Color(0xFFF3F1EE), dMuted = Color(0xFFA9A5AE), dLine = Color(0xFF34323A);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? const Color(0xFFD41F27) : Brand.crimson,
    onPrimary: Colors.white,
    secondary: Brand.gold,
    onSecondary: Brand.ink,
    error: Brand.crimsonDeep,
    onError: Colors.white,
    surface: dark ? Brand.dSurface : Brand.surface,
    onSurface: dark ? Brand.dFg : Brand.ink,
    surfaceContainerHighest: dark ? Brand.dSurface2 : Brand.surface2,
    outline: dark ? Brand.dLine : Brand.line,
    onSurfaceVariant: dark ? Brand.dMuted : Brand.muted,
  );
  final body = GoogleFonts.manropeTextTheme().apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  final display = GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, color: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Brand.dBg : Brand.bg,
    textTheme: body.copyWith(
      headlineLarge: display.copyWith(fontSize: 30),
      headlineMedium: display.copyWith(fontSize: 26),
      headlineSmall: display.copyWith(fontSize: 22),
      titleLarge: body.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 15),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 14),
      labelSmall: body.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .9),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      side: BorderSide(color: scheme.outline, width: 1.5), foregroundColor: scheme.onSurface,
      textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800),
    )),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface, indicatorColor: Colors.transparent, height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.manrope(
        fontSize: 10, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w700,
        color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
    ),
    dividerColor: scheme.outline,
  );
}


/// Light / dark appearance, chosen in Settings and remembered on the device. Dark is the default.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'rc_theme';
  @override
  ThemeMode build() {
    SharedPreferences.getInstance().then((p) { final v = p.getString(_key); if (v == 'light') state = ThemeMode.light; });
    return ThemeMode.dark;
  }
  Future<void> set(ThemeMode m) async { state = m; (await SharedPreferences.getInstance()).setString(_key, m == ThemeMode.light ? 'light' : 'dark'); }
}
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// "Appearance: Dark | Light" — used in the parents' Settings and the staff "My settings".
class ThemeChoice extends ConsumerWidget {
  const ThemeChoice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('Dark')),
        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('Light')),
      ],
      selected: {mode == ThemeMode.light ? ThemeMode.light : ThemeMode.dark},
      showSelectedIcon: false,
      onSelectionChanged: (v) => ref.read(themeModeProvider.notifier).set(v.first),
    );
  }
}
