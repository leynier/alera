import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models.dart';
import '../network/mobile_runtime_client.dart';
import '../theme/alera_tokens.dart';

class TerminalPreview extends StatefulWidget {
  const TerminalPreview({
    super.key,
    required this.client,
    required this.workspaces,
  });

  final MobileTerminalClient client;
  final List<WorkspaceSummary> workspaces;

  @override
  State<TerminalPreview> createState() => _TerminalPreviewState();
}

class _TerminalPreviewState extends State<TerminalPreview> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  StreamSubscription<MobileTerminalOutputEvent>? _outputSub;
  String? _sessionId;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 1000, onOutput: _handleTerminalOutput);
    _controller = TerminalController();
    _terminal.write('Alera\r\n');
    _terminal.write('No Session Attached\r\n');
    _outputSub = widget.client.terminalOutput.listen((event) {
      if (event.sessionId != _sessionId) {
        return;
      }
      _terminal.write(utf8.decode(event.data, allowMalformed: true));
    });
  }

  @override
  void dispose() {
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(widget.client.detachTerminal(sessionId));
    }
    unawaited(_outputSub?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || widget.workspaces.isEmpty) {
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final workspace = widget.workspaces.first;
      final session = await _openRunningTerminal(workspace.id);
      _sessionId = session.attachment.sessionId;
      _terminal.write('\r\nAttached To ${workspace.name}\r\n\r\n');
      if (session.attachment.snapshot.isNotEmpty) {
        _terminal.write(
          utf8.decode(session.attachment.snapshot, allowMalformed: true),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  Future<MobileTerminalSession> _openRunningTerminal(String workspaceId) async {
    final existingTab = await _firstTerminalTab(workspaceId);
    if (existingTab == null) {
      return widget.client.createTerminal(workspaceId);
    }
    final attached = await widget.client.attachTerminal(existingTab.id);
    if (attached.attachment.running) {
      return attached;
    }
    await widget.client.detachTerminal(attached.attachment.sessionId);
    final created = await widget.client.createTerminal(workspaceId);
    if (!created.attachment.running) {
      throw StateError('Terminal Session Is Not Running.');
    }
    return created;
  }

  Future<WorkspaceTabSummary?> _firstTerminalTab(String workspaceId) async {
    final tabs = await widget.client.listTabs(workspaceId);
    for (final tab in tabs) {
      if (tab.kind == 'terminal') {
        return tab;
      }
    }
    return null;
  }

  void _handleTerminalOutput(String data) {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    unawaited(_writeTerminalInput(sessionId, data));
  }

  Future<void> _writeTerminalInput(String sessionId, String data) async {
    try {
      await widget.client.writeTerminal(sessionId, utf8.encode(data));
    } on Object catch (error) {
      if (!mounted || _sessionId != sessionId) {
        return;
      }
      setState(() {
        _sessionId = null;
        _error = 'Terminal Input Failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: AleraTokens.border),
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: AleraTokens.contentPadding,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _sessionId == null ? 'Detached' : 'Attached',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _starting || widget.workspaces.isEmpty
                        ? null
                        : _start,
                    icon: _starting
                        ? const SizedBox.square(
                            dimension: AleraTokens.spaceLg,
                            child: CircularProgressIndicator(
                              strokeWidth: AleraTokens.strokeSm,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.spaceLg,
                  0,
                  AleraTokens.spaceLg,
                  AleraTokens.spaceMd,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              height: AleraTokens.terminalPreviewHeight,
              child: TerminalView(
                _terminal,
                controller: _controller,
                autofocus: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
