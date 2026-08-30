import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

Future<void> showTerminalPulseDialog(
  BuildContext context,
  TerminalSessionHandle session,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => TerminalPulseDialog(session: session),
  );
}

class TerminalPulseDialog extends StatefulWidget {
  const TerminalPulseDialog({super.key, required this.session});

  final TerminalSessionHandle session;

  @override
  State<TerminalPulseDialog> createState() => _TerminalPulseDialogState();
}

class _TerminalPulseDialogState extends State<TerminalPulseDialog> {
  late final TextEditingController _commandController;
  late final TextEditingController _delayController;
  late bool _armed;
  late bool _appendEnter;
  late int _delayMilliseconds;
  late double _delaySeconds;
  bool _saving = false;
  bool _applyingExternalState = false;
  bool _commandDirty = false;
  bool _delayDirty = false;
  bool _armedDirty = false;
  bool _appendEnterDirty = false;
  String? _localError;
  String? _externalError;

  @override
  void initState() {
    super.initState();
    final state = widget.session.terminalPulseState.value;
    _commandController = TextEditingController(
      text: state.configuration.command,
    );
    _armed = state.armed;
    _appendEnter = state.configuration.appendEnter;
    _delayMilliseconds = state.configuration.delayMilliseconds;
    _delaySeconds = _delayMilliseconds / 1000;
    _delayController = TextEditingController(
      text: _formatSeconds(_delayMilliseconds),
    );
    _commandController.addListener(_handleCommandEdited);
    _delayController.addListener(_handleDelayEdited);
    _externalError = state.error;
    widget.session.terminalPulseState.addListener(_handlePulseStateChanged);
  }

  @override
  void dispose() {
    widget.session.terminalPulseState.removeListener(_handlePulseStateChanged);
    _commandController.removeListener(_handleCommandEdited);
    _delayController.removeListener(_handleDelayEdited);
    _commandController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _handlePulseStateChanged() {
    final state = widget.session.terminalPulseState.value;
    if (!mounted) {
      return;
    }
    setState(() {
      _applyingExternalState = true;
      if (!_commandDirty) {
        _commandController.text = state.configuration.command;
      }
      if (!_delayDirty) {
        _delayMilliseconds = state.configuration.delayMilliseconds;
        _delaySeconds = _delayMilliseconds / 1000;
        _delayController.text = _formatSeconds(_delayMilliseconds);
      }
      if (!_armedDirty) {
        _armed = state.armed;
      }
      if (!_appendEnterDirty) {
        _appendEnter = state.configuration.appendEnter;
      }
      _externalError = state.error;
      _applyingExternalState = false;
    });
  }

  void _handleCommandEdited() {
    if (!_applyingExternalState) {
      _commandDirty = true;
    }
  }

  void _handleDelayEdited() {
    if (!_applyingExternalState) {
      _delayDirty = true;
    }
  }

  Future<void> _save() async {
    final command = _commandController.text;
    if (command.isEmpty) {
      setState(() => _localError = 'Terminal input is required.');
      return;
    }
    if (_delayDirty) {
      final parsedDelay = double.tryParse(_delayController.text.trim());
      if (parsedDelay == null || !parsedDelay.isFinite) {
        setState(() => _localError = 'Wait must be a valid number of seconds.');
        return;
      }
      _delayMilliseconds = (parsedDelay.clamp(0.1, 3600) * 1000).round();
    }
    _delaySeconds = _delayMilliseconds / 1000;
    _applyingExternalState = true;
    _delayController.text = _formatSeconds(_delayMilliseconds);
    _applyingExternalState = false;
    setState(() {
      _saving = true;
      _localError = null;
      _externalError = null;
    });
    try {
      await widget.session.configureTerminalPulse(
        configuration: TerminalPulseConfiguration(
          command: command,
          appendEnter: _appendEnter,
          delayMilliseconds: _delayMilliseconds,
        ),
        armed: _armed,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _localError = error.toString();
        });
      }
    }
  }

  String _formatSeconds(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final remainder = milliseconds.remainder(1000);
    if (remainder == 0) {
      return seconds.toString();
    }
    final fraction = remainder
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$seconds.$fraction';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Terminal Pulse',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Watch Git tracked and new untracked files in this workspace. The first change starts a fixed wait, then the configured input is sent once.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    AleraPanel(
                      clipBehavior: Clip.antiAlias,
                      children: <Widget>[
                        AleraSettingRow(
                          title: 'Armed',
                          description: 'Disarms automatically when this terminal process restarts.',
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Switch(
                              value: _armed,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() {
                                      _armed = value;
                                      _armedDirty = true;
                                    }),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AleraTokens.space16),
                          child: AleraTextField(
                            controller: _commandController,
                            labelText: 'Terminal Input',
                            hintText: 'r',
                            enabled: !_saving,
                            autofocus: true,
                            onChanged: (_) => _commandDirty = true,
                            onSubmitted: (_) {
                              if (!_saving) {
                                unawaited(_save());
                              }
                            },
                          ),
                        ),
                        AleraSettingRow(
                          title: 'Send Enter',
                          description:
                              'Append Enter after writing the terminal input.',
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Switch(
                              value: _appendEnter,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() {
                                      _appendEnter = value;
                                      _appendEnterDirty = true;
                                    }),
                            ),
                          ),
                        ),
                        AleraSettingRow(
                          title: 'Wait',
                          description: 'Starts with the first change and is not extended by later changes.',
                          child: IgnorePointer(
                            ignoring: _saving,
                            child: AleraNumberField(
                              controller: _delayController,
                              value: _delaySeconds,
                              min: 0.1,
                              max: 3600,
                              step: 1,
                              decimalPlaces: 3,
                              suffix: 's',
                              onChanged: (value) => setState(() {
                                _delaySeconds = value;
                                _delayMilliseconds = (value * 1000).round();
                                _delayDirty = true;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((_localError ?? _externalError) != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        (_localError ?? _externalError)!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving Changes' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
