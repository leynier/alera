import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/hosts/presentation/host_list_screen.dart';
import 'package:alera_mobile/src/features/updater/presentation/mobile_update_prompt.dart';
import 'package:flutter/material.dart';

class AleraMobileApp extends StatelessWidget {
  const AleraMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alera',
      debugShowCheckedModeBanner: false,
      theme: buildAleraMobileDarkTheme(),
      // Wrapping the first route rather than `builder`, which mounts above the
      // Navigator and leaves the prompt without one to push a dialog onto.
      home: const MobileUpdatePrompt(child: HostListScreen()),
    );
  }
}
