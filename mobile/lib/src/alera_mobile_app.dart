import 'package:flutter/material.dart';

import 'screens/host_list_screen.dart';
import 'storage/host_repository.dart';
import 'theme/alera_tokens.dart';

class AleraMobileApp extends StatelessWidget {
  const AleraMobileApp({super.key, this.hostRepository});

  final HostRepository? hostRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alera Mobile',
      debugShowCheckedModeBanner: false,
      theme: _darkTheme,
      home: HostListScreen(
        hostRepository: hostRepository ?? LocalHostRepository(),
      ),
    );
  }
}

final ThemeData _darkTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: AleraTokens.accent,
    onPrimary: AleraTokens.onAccent,
    primaryContainer: AleraTokens.surfaceElevated,
    onPrimaryContainer: AleraTokens.foreground,
    secondary: AleraTokens.accent,
    onSecondary: AleraTokens.onAccent,
    secondaryContainer: AleraTokens.surfaceVariant,
    onSecondaryContainer: AleraTokens.foreground,
    surface: AleraTokens.surface,
    onSurface: AleraTokens.foreground,
    surfaceContainerLowest: AleraTokens.background,
    surfaceContainerLow: AleraTokens.surface,
    surfaceContainer: AleraTokens.surfaceVariant,
    surfaceContainerHigh: AleraTokens.surfaceElevated,
    surfaceContainerHighest: AleraTokens.surfaceElevated,
    onSurfaceVariant: AleraTokens.foregroundMuted,
    error: AleraTokens.error,
    onError: AleraTokens.onError,
    outline: AleraTokens.border,
    outlineVariant: AleraTokens.borderSubtle,
  ),
  scaffoldBackgroundColor: AleraTokens.background,
  fontFamily: 'Inter',
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: AleraTokens.background,
    foregroundColor: AleraTokens.foreground,
    centerTitle: false,
  ),
  cardTheme: const CardThemeData(
    color: AleraTokens.surface,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AleraTokens.radiusSm)),
      side: BorderSide(color: AleraTokens.border),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AleraTokens.radiusSm)),
    ),
    filled: true,
    fillColor: AleraTokens.surface,
  ),
);
