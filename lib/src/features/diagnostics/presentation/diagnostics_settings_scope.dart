import 'package:alera/src/features/diagnostics/application/diagnostics_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps the logger level and crash-reporting switch in sync with settings.
///
/// Mounted in the shell rather than read at startup because settings load
/// asynchronously: without this, the values chosen at boot would stay in force
/// for the whole session and toggling the setting would do nothing.
class DiagnosticsSettingsScope extends ConsumerWidget {
  const DiagnosticsSettingsScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(diagnosticsSettingsApplierProvider);
    return child;
  }
}
