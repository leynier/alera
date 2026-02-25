import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast_host.dart';
import 'package:flutter/material.dart';

class AleraApp extends StatelessWidget {
  const AleraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alera',
      home: const AleraShellPage(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            const AleraToastHost(),
          ],
        );
      },
      theme: buildAleraDarkTheme(),
      darkTheme: buildAleraDarkTheme(),
      themeMode: ThemeMode.dark,
    );
  }
}
