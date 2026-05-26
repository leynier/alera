import 'package:alera/src/app/app.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.configure();
  await initializeGhosttyVteWeb();

  runApp(const ProviderScope(child: AleraApp()));
}
