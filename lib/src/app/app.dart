import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/app_window/presentation/app_window_lifecycle_scope.dart';
import 'package:alera/src/features/diagnostics/presentation/diagnostics_settings_scope.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/text_actions/presentation/text_actions_scope.dart';
import 'package:alera/src/features/updater/presentation/update_availability_watch.dart';
import 'package:alera/src/features/runtime_host/presentation/runtime_host_quit_gate_scope.dart';
import 'package:flutter/material.dart';

class AleraApp extends StatelessWidget {
  const AleraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAleraAppName,
      home: const RuntimeHostQuitGateScope(child: AleraShellPage()),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AppWindowLifecycleScope(
          child: DiagnosticsSettingsScope(
            child: UpdateAvailabilityWatch(
              child: Stack(
                children: <Widget>[
                  TextActionsScope(child: child ?? const SizedBox.shrink()),
                  const AleraToastHost(),
                ],
              ),
            ),
          ),
        );
      },
      theme: aleraDarkTheme,
      darkTheme: aleraDarkTheme,
      themeMode: ThemeMode.dark,
    );
  }
}
