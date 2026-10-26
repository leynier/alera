import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/error_reporting/application/error_reporting_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// Mounts the toast host with the AI Assist error clarification wired in,
/// and writes every error the user is shown to the diagnostics log, so a
/// failure seen on screen is never missing from a diagnostics bundle.
class const ErrorNotificationHost({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ErrorNotificationHost> createState() =>
      _ErrorNotificationHostState();
}

class _ErrorNotificationHostState extends ConsumerState<ErrorNotificationHost> {
  static final Logger _logger = Logger('UserVisibleErrors');

  StreamSubscription<AleraToastData>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AleraToast.stream.listen(_record);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _record(AleraToastData toast) {
    switch (toast.tone) {
      case AleraToastTone.error:
        _logger.warning('Error shown to the user: ${toast.message}');
      case AleraToastTone.warning:
        _logger.info('Warning shown to the user: ${toast.message}');
      case AleraToastTone.success || AleraToastTone.info:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiAssist = ref.watch(
      settingsControllerProvider.select((settings) => settings.aiAssist),
    );
    final clarify = aiAssist.enabled && aiAssist.clarifyErrorMessages;
    return AleraToastHost(
      clarifyError: clarify ? ref.read(aiErrorClarifierProvider).clarify : null,
      clarifyingCaption: 'Clarifying with AI Assist…',
      clarifiedCaption: 'Clarified by AI Assist',
    );
  }
}
