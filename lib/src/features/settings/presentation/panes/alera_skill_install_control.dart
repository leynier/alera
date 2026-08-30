import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:alera/src/features/settings/presentation/panes/skill_install_output_dialog.dart';
import 'package:flutter/material.dart';

class const AleraSkillInstallStatus(
  final String summary, {
  this.detail = '',
  final bool needsAttention = false,
}) {
  /// Full installer output, shown on demand. The inline summary is one line.
  final String detail;
}

typedef AleraSkillInstaller = Future<AleraSkillInstallStatus> Function(
  AleraCliSkillRunner runner,
);
typedef AleraSkillCommandBuilder = String Function(AleraCliSkillRunner runner);

/// Installs in process and reports afterwards, for setup that is more than one
/// shell command. Single-command skills use
/// [AleraSkillTerminalInstallControl] instead, which runs them in front of the
/// user.
class const AleraSkillInstallControl({
  super.key,
  required final AleraSkillInstaller install,
  final String installLabel = 'Install / Update',
  final String installingLabel = 'Installing',
}) extends StatefulWidget {
  @override
  State<AleraSkillInstallControl> createState() =>
      _AleraSkillInstallControlState();
}

class _AleraSkillInstallControlState extends State<AleraSkillInstallControl> {
  final GlobalKey<PopupMenuButtonState<AleraCliSkillRunner>> _runnerMenuKey =
      GlobalKey<PopupMenuButtonState<AleraCliSkillRunner>>();
  bool _installing = false;
  AleraSkillInstallStatus? _status;
  AleraCliSkillRunner _runner = .auto;

  Future<void> _install() async {
    if (_installing) {
      return;
    }
    setState(() {
      _installing = true;
      _status = null;
    });
    try {
      final result = await widget.install(_runner);
      if (mounted) {
        setState(() => _status = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = AleraSkillInstallStatus(
            'Install failed',
            detail: '$error',
            needsAttention: true,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _installing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      crossAxisAlignment: .end,
      mainAxisSize: .min,
      children: <Widget>[
        Wrap(
          alignment: .end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            SizedBox(
              height: kSupportControlHeight,
              child: PopupMenuButton<AleraCliSkillRunner>(
                key: _runnerMenuKey,
                enabled: !_installing,
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
                  onPressed: _installing
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
            if (status != null && status.detail.isNotEmpty)
              SizedBox(
                height: kSupportControlHeight,
                child: OutlinedButton.icon(
                  onPressed: () => SkillInstallOutputDialog.show(
                    context,
                    title: 'Installer Output',
                    output: status.detail,
                  ),
                  icon: const Icon(AleraIcons.terminal, size: 16),
                  label: const Text('View Output'),
                ),
              ),
            SizedBox(
              height: kSupportControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AleraTokens.foreground,
                        ),
                      )
                    : const Icon(AleraIcons.download, size: 16),
                label: Text(
                  _installing ? widget.installingLabel : widget.installLabel,
                ),
              ),
            ),
          ],
        ),
        if (status != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            status.summary,
            textAlign: .right,
            maxLines: 2,
            overflow: .ellipsis,
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
