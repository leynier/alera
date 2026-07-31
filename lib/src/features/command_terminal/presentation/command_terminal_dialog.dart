import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runs one command in a real PTY, in front of the user.
///
/// The command starts on its own once the shell is up, so this is a place to
/// watch and to answer: a `sudo` password prompt, an `apt` confirmation, a
/// installer asking which version to keep. Nothing here polls for completion -
/// the shell outlives the command, and the returning prompt is the signal.
class CommandTerminalDialog extends StatefulWidget {
  const CommandTerminalDialog({
    super.key,
    required this.request,
    required this.session,
  });

  final CommandTerminalRequest request;
  final TerminalSessionHandle session;

  @override
  State<CommandTerminalDialog> createState() => _CommandTerminalDialogState();
}

class _CommandTerminalDialogState extends State<CommandTerminalDialog> {
  bool _allowPop = false;

  /// Confirms before closing while the shell is alive, because closing kills
  /// the whole process tree and a half-applied package upgrade is worth one
  /// question. A shell the user already exited closes without asking.
  Future<void> _requestClose() async {
    if (_allowPop) {
      return;
    }
    if (widget.session.isRunning) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const AleraConfirmDialog(
          title: 'Stop Running Command?',
          message:
              'Closing Will End The Command And Every Process It Started. '
              'Anything Halfway Through Will Stay Halfway Through.',
          confirmLabel: 'Stop And Close',
          destructive: true,
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = widget.request.description;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: AleraDialog(
        maxWidth: AleraTokens.dialogTerminalWidth,
        child: SizedBox(
          height: AleraTokens.dialogTerminalHeight,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AleraDialogHeader(
                  title: widget.request.title,
                  onClose: () => unawaited(_requestClose()),
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
                const SizedBox(height: AleraTokens.space12),
                AleraCommandLine(
                  command: widget.request.command,
                  backgroundColor: AleraTokens.surfaceVariant,
                  trailing: AleraIconButton(
                    tooltip: 'Copy Command',
                    icon: AleraIcons.copy,
                    onPressed: () => unawaited(
                      Clipboard.setData(
                        ClipboardData(text: widget.request.command),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AleraTokens.space12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AleraTokens.borderSubtle),
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusMd,
                        ),
                      ),
                      child: TerminalSurface(
                        session: widget.session,
                        autofocus: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AleraTokens.space12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    FilledButton(
                      onPressed: () => unawaited(_requestClose()),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
