import 'package:alera/src/app/app.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.configure();

  runApp(
    const ProviderScope(
      child: AleraApp(),
    ),
  );
}
