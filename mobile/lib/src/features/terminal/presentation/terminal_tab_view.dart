import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_floating_pill_button.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_input_mode_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/mobile_terminal_scrollback.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_osc52_clipboard.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_restore_progress.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_touch_scroll.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_attachment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_output_batcher.dart';
import 'package:logging/logging.dart';
import 'package:xterm2/xterm.dart';

part 'terminal_attachment_actions.dart';
part 'terminal_surface.dart';
part 'terminal_tab_state_widgets.dart';

/// One terminal tab filling the available space, with the quick-key bar and
/// the compose/direct input modes stacked above the keyboard.
class const TerminalTabView({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String tabId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends ConsumerState<TerminalTabView> {
  final GlobalKey<_TerminalSurfaceState> _surfaceKey =
      GlobalKey<_TerminalSurfaceState>();
  bool _refreshing = false;
  // Latches once the tab has attached, so a reconnect keeps the input bars
  // that a first start has not earned yet.
  bool _hadSession = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      terminalSessionControllerProvider(widget.hostId, widget.tabId),
    );
    final inputMode = ref.watch(
      terminalInputModeControllerProvider(widget.tabId),
    );
    final accessoryKeys =
        ref
            .watch(terminalAccessoryLayoutControllerProvider)
            .value
            ?.visibleKeys() ??
        const <TerminalAccessoryKey>[];
    final notifier = ref.read(
      terminalSessionControllerProvider(widget.hostId, widget.tabId).notifier,
    );
    if (session is AsyncData<TerminalTabSession>) {
      _hadSession = true;
    }
    // Only the emulator swaps with the session state. The input bars below it
    // stay mounted across a reconnect or a restore, because rebuilding them
    // throws away the composed text and disposes the controller an in-flight
    // attachment pick is waiting to write into.
    final surface = switch (session) {
      AsyncData(value: final tabSession) => _TerminalSurface(
        key: _surfaceKey,
        session: tabSession,
        inputMode: inputMode,
        onInput: (data) => notifier.write(utf8.encode(data)),
        onViewportResize: notifier.resize,
        onReconnect: notifier.reconnect,
      ),
      AsyncError(:final error) => _SessionError(
        error: error,
        onReconnect: notifier.reconnect,
        onRestart: notifier.supportsRestart
            ? () => _confirmRestart(context, notifier)
            : null,
      ),
      AsyncLoading(:final progress) => _SessionLoading(
        operation: switch (progress) {
          0.25 => _TerminalLoadingOperation.reconnecting,
          0.75 => _TerminalLoadingOperation.restarting,
          _ => _TerminalLoadingOperation.starting,
        },
      ),
    };
    final content = Column(
      children: <Widget>[
        Expanded(child: surface),
        // A first start has nothing to compose against yet; only a tab that
        // has already attached keeps its bars through the loading state.
        if (_hadSession) ...<Widget>[
          if (inputMode == TerminalInputMode.direct) const _DirectModeBanner(),
          TerminalAccessoryBar(
            keys: accessoryKeys,
            onKey: notifier.write,
            onAction: (action) => switch (action) {
              TerminalAccessoryAction.paste => _pasteClipboard(notifier),
            },
          ),
          if (inputMode == TerminalInputMode.compose)
            TerminalComposeBar(
              hostId: widget.hostId,
              tabId: widget.tabId,
              onSend: (text, {required withEnter}) {
                // The reply lands at the bottom; a reader still parked in
                // history would otherwise not see their own prompt go out.
                _surfaceKey.currentState?.scrollToLatest();
                unawaited(
                  notifier.sendComposedText(text, withEnter: withEnter),
                );
              },
              onPickAttachments: _canAttach ? _pickAttachments : null,
            ),
        ],
      ],
    );
    return Stack(
      fit: .expand,
      children: <Widget>[
        content,
        // Terminal-level controls stack in one corner rail rather than sitting
        // in the key strip, which belongs to what gets typed.
        Positioned(
          top: AleraTokens.spaceXs,
          right: AleraTokens.spaceXs,
          child: Column(
            children: <Widget>[
              AleraIconButton(
                tooltip: _refreshing
                    ? 'Refreshing Terminal'
                    : 'Refresh Terminal',
                icon: _refreshing ? AleraIcons.loading : AleraIcons.refresh,
                backgroundColor: AleraTokens.surfaceElevated,
                borderColor: AleraTokens.borderSubtle,
                onPressed: _refreshing ? null : _refreshTerminal,
              ),
              const SizedBox(height: AleraTokens.spaceXs),
              AleraIconButton(
                tooltip: inputMode == TerminalInputMode.compose
                    ? 'Switch To Direct Input'
                    : 'Switch To Compose Input',
                icon: inputMode == TerminalInputMode.compose
                    ? Icons.keyboard_alt_outlined
                    : Icons.bolt,
                backgroundColor: inputMode == TerminalInputMode.direct
                    ? AleraTokens.accentSubtle
                    : AleraTokens.surfaceElevated,
                borderColor: AleraTokens.borderSubtle,
                onPressed: ref
                    .read(
                      terminalInputModeControllerProvider(widget.tabId)
                          .notifier,
                    )
                    .toggle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pasteClipboard(TerminalSessionController notifier) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard has no text')),
          );
        }
        return;
      }
      await notifier.pasteText(text);
    } catch (error, stackTrace) {
      Logger('TerminalTabView')
          .warning('terminal clipboard paste failed', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not paste clipboard')),
        );
      }
    }
  }

  Future<void> _refreshTerminal() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await ref
          .read(
            terminalSessionControllerProvider(
              widget.hostId,
              widget.tabId,
            ).notifier,
          )
          .refreshViewport();
      await _surfaceKey.currentState?.refreshRendering();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _confirmRestart(
    BuildContext context,
    TerminalSessionController notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restart Terminal?'),
          content: const Text(
            'This will stop the current process tree and start a new shell. Terminal history will be preserved.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restart Terminal'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await notifier.restartTerminal();
    }
  }
}
