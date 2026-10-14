import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/application/agent_provider_settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// How a settings screen reports a write. An edit another device made first
/// is not an error to apologize for: the screen reloads and says so.
mixin AgentProviderSettingsFeedback<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  static final Logger _logger = Logger('AgentProviderSettings');

  /// Reloads what the screen shows after a lost race.
  void reloadSettings();

  Future<void> runSettingsWrite(
    String what,
    Future<void> Function() write,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await write();
    } on Object catch (error, stackTrace) {
      _logger.warning(what, error, stackTrace);
      final conflict = agentProviderSettingsConflict(error);
      if (conflict && mounted) reloadSettings();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            conflict
                ? 'These settings changed on another device. Showing the '
                      'latest values; try again.'
                : agentChatErrorMessage(error),
          ),
        ),
      );
    }
  }
}
