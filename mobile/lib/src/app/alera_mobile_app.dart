import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/hosts/presentation/host_list_screen.dart';
import 'package:flutter/material.dart';

class AleraMobileApp extends StatelessWidget {
  const AleraMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alera',
      debugShowCheckedModeBanner: false,
      theme: buildAleraMobileDarkTheme(),
      home: const HostListScreen(),
    );
  }
}
