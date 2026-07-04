import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/settings/infra/alera_cli_registration_service.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraCliSkillControl extends ConsumerStatefulWidget {
  const AleraCliSkillControl({super.key});

  @override
  ConsumerState<AleraCliSkillControl> createState() =>
      _AleraCliSkillControlState();
}

class _AleraCliSkillControlState extends ConsumerState<AleraCliSkillControl> {
  bool _installing = false;
  String? _status;
  AleraCliSkillRunner _runner = AleraCliSkillRunner.auto;

  Future<void> _install() async {
    if (_installing) {
      return;
    }
    setState(() {
      _installing = true;
      _status = null;
    });
    try {
      final result = await ref
          .read(aleraCliSkillServiceProvider)
          .installOrUpdate(runner: _runner);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = result.summary;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Install Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(
      ClipboardData(text: aleraCliSkillInstallCommand(runner: _runner)),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Install Command Copied';
    });
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
                child: IgnorePointer(
                  child: OutlinedButton.icon(
                    onPressed: _installing ? null : () {},
                    icon: const Icon(AleraIcons.chevronDown, size: 16),
                    label: Text(_runner.label),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: kSupportControlHeight,
              child: OutlinedButton.icon(
                onPressed: _installing ? null : _copyCommand,
                icon: const Icon(AleraIcons.copy, size: 16),
                label: const Text('Copy'),
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
                label: Text(_installing ? 'Installing' : 'Install / Update'),
              ),
            ),
          ],
        ),
        if (status != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            status,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status.startsWith('Install Failed')
                  ? AleraTokens.error
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class AleraCliRegistrationControl extends ConsumerStatefulWidget {
  const AleraCliRegistrationControl({super.key});

  @override
  ConsumerState<AleraCliRegistrationControl> createState() =>
      _AleraCliRegistrationControlState();
}

class _AleraCliRegistrationControlState
    extends ConsumerState<AleraCliRegistrationControl> {
  bool _busy = false;
  AleraCliRegistrationStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refresh);
  }

  Future<void> _refresh() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(aleraCliRegistrationServiceProvider)
          .status();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = null;
        _error = 'Registration Check Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _install() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(aleraCliRegistrationServiceProvider)
          .installOrUpdate();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Registration Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final error = _error;
    final hasConflict =
        status?.state == AleraCliRegistrationState.conflict ||
        status?.state == AleraCliRegistrationState.unsupported;
    final ready = status?.ready ?? false;
    final summary = error ?? status?.summary;
    final detail = error == null ? status?.detail : null;
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
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AleraTokens.foreground,
                        ),
                      )
                    : const Icon(AleraIcons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ),
            SizedBox(
              height: kSupportControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: _busy || hasConflict ? null : _install,
                icon: const Icon(AleraIcons.terminal, size: 16),
                label: Text(ready ? 'Update' : 'Register'),
              ),
            ),
          ],
        ),
        if (summary != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            summary,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: error != null || hasConflict
                  ? AleraTokens.error
                  : ready
                  ? AleraTokens.success
                  : AleraTokens.foregroundMuted,
            ),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space2),
            Text(
              detail,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
