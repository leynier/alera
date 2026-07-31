import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:flutter/material.dart';

typedef AleraSkillTerminalRunner =
    Future<void> Function(BuildContext context, CommandTerminalRequest request);

/// Work that still has to happen in Dart once the installer command is done,
/// such as reconciling agent status hooks. Returning null leaves the status
/// line empty.
typedef AleraSkillTerminalFollowUp =
    Future<AleraSkillInstallStatus?> Function();

/// Installs a skill by running its command in a terminal dialog.
///
/// The installer resolves `npx` out of the user's interactive shell, which is
/// where it actually is, and anything it asks for has somewhere to be answered.
/// There is no `View Output` here because the output is no longer something
/// that happens offscreen and gets shown afterwards.
class AleraSkillTerminalInstallControl extends StatefulWidget {
  const AleraSkillTerminalInstallControl({
    super.key,
    required this.dialogTitle,
    required this.commandFor,
    required this.runCommand,
    this.followUp,
    this.installLabel = 'Install / Update',
    this.runningLabel = 'Running',
  });

  final String dialogTitle;
  final AleraSkillCommandBuilder commandFor;
  final AleraSkillTerminalRunner runCommand;
  final AleraSkillTerminalFollowUp? followUp;
  final String installLabel;
  final String runningLabel;

  @override
  State<AleraSkillTerminalInstallControl> createState() =>
      _AleraSkillTerminalInstallControlState();
}

class _AleraSkillTerminalInstallControlState
    extends State<AleraSkillTerminalInstallControl> {
  final GlobalKey<PopupMenuButtonState<AleraCliSkillRunner>> _runnerMenuKey =
      GlobalKey<PopupMenuButtonState<AleraCliSkillRunner>>();
  bool _running = false;
  AleraSkillInstallStatus? _status;
  AleraCliSkillRunner _runner = AleraCliSkillRunner.auto;

  Future<void> _run() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _status = null;
    });
    try {
      await widget.runCommand(
        context,
        CommandTerminalRequest(
          title: widget.dialogTitle,
          command: widget.commandFor(_runner),
          description:
              'The Installer Runs Here. Answer Any Prompt In The Terminal.',
        ),
      );
      // The follow-up reads providers through the wrapper's ref, which stops
      // being valid once this control leaves the tree.
      if (!mounted) {
        return;
      }
      final followUp = await widget.followUp?.call();
      if (mounted) {
        setState(() => _status = followUp);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = AleraSkillInstallStatus(
            'Install Failed: $error',
            needsAttention: true,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            SizedBox(
              height: kSupportControlHeight,
              child: PopupMenuButton<AleraCliSkillRunner>(
                key: _runnerMenuKey,
                enabled: !_running,
                tooltip: 'Select Runner',
                onSelected: (runner) {
                  setState(() {
                    _runner = runner;
                    _status = null;
                  });
                },
                itemBuilder: (context) => <PopupMenuEntry<AleraCliSkillRunner>>[
                  for (final runner in AleraCliSkillRunner.values)
                    AleraDropdownEntry<AleraCliSkillRunner>(
                      value: runner,
                      label: runner.label,
                      selected: runner == _runner,
                    ),
                ],
                child: OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () => _runnerMenuKey.currentState?.showButtonMenu(),
                  style: ButtonStyle(
                    mouseCursor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.disabled)
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click;
                    }),
                  ),
                  icon: const Icon(AleraIcons.chevronDown, size: 16),
                  label: Text(_runner.label),
                ),
              ),
            ),
            SizedBox(
              height: kSupportControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: _running ? null : _run,
                icon: const Icon(AleraIcons.terminal, size: 16),
                label: Text(
                  _running ? widget.runningLabel : widget.installLabel,
                ),
              ),
            ),
          ],
        ),
        if (status != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            status.summary,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status.needsAttention
                  ? AleraTokens.error
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}
