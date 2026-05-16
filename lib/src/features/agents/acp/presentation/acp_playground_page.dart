import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agents/acp/application/acp_agent_orchestrator.dart';
import 'package:alera/src/features/agents/acp/infrastructure/codex_acp_client.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Experimental playground for the ACP backend. Independent from the regular
/// Codex session flow — owns its own `CodexAcpClient` + `AcpAgentOrchestrator`
/// and tears them down on dispose. Lets the user start a session against
/// `codex-acp`, send prompts, watch streamed events, and approve/reject
/// permission requests.
class AcpPlaygroundPage extends ConsumerStatefulWidget {
  const AcpPlaygroundPage({super.key});

  @override
  ConsumerState<AcpPlaygroundPage> createState() => _AcpPlaygroundPageState();
}

class _AcpPlaygroundPageState extends ConsumerState<AcpPlaygroundPage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AcpEntry> _entries = <_AcpEntry>[];
  final List<_PendingApproval> _approvals = <_PendingApproval>[];

  StreamSubscription<AgentOrchestratorEvent>? _sub;
  AcpAgentOrchestrator? _orchestrator;
  String? _workspacePath;
  String? _sessionId;
  bool _booting = false;
  bool _starting = false;
  bool _sending = false;

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_orchestrator?.close());
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickWorkspace() async {
    try {
      final selected = await getDirectoryPath(
        confirmButtonText: 'Select workspace',
      );
      if (!mounted || selected == null || selected.trim().isEmpty) {
        return;
      }
      setState(() => _workspacePath = selected.trim());
    } catch (error) {
      if (!mounted) {
        return;
      }
      _logLocal('Folder picker unavailable: $error');
    }
  }

  Future<void> _startSession() async {
    final cwd = _workspacePath;
    if (cwd == null || cwd.isEmpty) {
      _logLocal('Pick a workspace first.');
      return;
    }
    setState(() => _starting = true);
    try {
      var orchestrator = _orchestrator;
      if (orchestrator == null) {
        setState(() => _booting = true);
        final processRunner = ref.read(processRunnerProvider);
        final client = CodexAcpClient(processRunner: processRunner);
        orchestrator = AcpAgentOrchestrator(client);
        await orchestrator.boot();
        if (!mounted) {
          await orchestrator.close();
          return;
        }
        _sub = orchestrator.events.listen(_onEvent);
        setState(() {
          _orchestrator = orchestrator;
          _booting = false;
        });
      }
      final sessionId = await orchestrator.ensureThread(cwd: cwd);
      if (!mounted) {
        return;
      }
      setState(() => _sessionId = sessionId);
      _logLocal('Session ready: $sessionId');
    } catch (error) {
      _logLocal('Failed to start session: $error');
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
          _booting = false;
        });
      }
    }
  }

  Future<void> _sendPrompt() async {
    final orchestrator = _orchestrator;
    final sessionId = _sessionId;
    final text = _promptController.text.trim();
    if (orchestrator == null || sessionId == null || text.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      _logLocal('You: $text');
      await orchestrator.runTurn(
        threadId: sessionId,
        input: <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': text},
        ],
        cwd: _workspacePath,
      );
      _promptController.clear();
    } catch (error) {
      _logLocal('Prompt failed: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancel() async {
    final orchestrator = _orchestrator;
    final sessionId = _sessionId;
    if (orchestrator == null || sessionId == null) {
      return;
    }
    try {
      await orchestrator.interrupt(threadId: sessionId);
      _logLocal('Cancel requested.');
    } catch (error) {
      _logLocal('Cancel failed: $error');
    }
  }

  Future<void> _approve(_PendingApproval approval, String optionId) async {
    final orchestrator = _orchestrator;
    if (orchestrator == null) {
      return;
    }
    try {
      await orchestrator.approveRequest(approval.requestId, optionId: optionId);
      _logLocal('Approved $optionId for: ${approval.description}');
    } catch (error) {
      _logLocal('Approve failed: $error');
    } finally {
      if (mounted) {
        setState(() => _approvals.remove(approval));
      }
    }
  }

  Future<void> _decline(_PendingApproval approval) async {
    final orchestrator = _orchestrator;
    if (orchestrator == null) {
      return;
    }
    try {
      await orchestrator.declineRequest(approval.requestId);
      _logLocal('Declined: ${approval.description}');
    } catch (error) {
      _logLocal('Decline failed: $error');
    } finally {
      if (mounted) {
        setState(() => _approvals.remove(approval));
      }
    }
  }

  void _onEvent(AgentOrchestratorEvent event) {
    if (!mounted) {
      return;
    }
    switch (event) {
      case AgentNotificationEvent():
        _logEvent(event.method, event.payload);
      case AgentApprovalRequestEvent():
        // ACP options come embedded in the request params, which we lose by
        // the time we hit AgentApprovalRequestEvent (it carries only the
        // description). MVP shows two canonical choices; real wiring can pass
        // them through when we extract a richer event type.
        setState(() {
          _approvals.add(
            _PendingApproval(
              requestId: event.requestId,
              description: event.description,
              options: const <String>['allow', 'allow_always'],
            ),
          );
        });
        _logEvent(event.method, <String, dynamic>{
          'description': event.description,
          'requestId': event.requestId.toString(),
        });
      case AgentToolCallRequestEvent():
        _logEvent('tool_call', <String, dynamic>{'tool': event.tool});
      case AgentUserInputRequestEvent():
        _logEvent('user_input_request', <String, dynamic>{
          'questions': event.questions,
        });
    }
  }

  void _logLocal(String message) {
    setState(
      () => _entries.add(
        _AcpEntry(
          method: 'local',
          payload: <String, dynamic>{'message': message},
        ),
      ),
    );
    _scrollToEnd();
  }

  void _logEvent(String method, Map<String, dynamic> payload) {
    setState(() => _entries.add(_AcpEntry(method: method, payload: payload)));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ACP playground (experimental)')),
      body: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(theme),
            const SizedBox(height: AleraTokens.space12),
            if (_approvals.isNotEmpty) ...<Widget>[
              ..._approvals.map(_buildApprovalCard),
              const SizedBox(height: AleraTokens.space12),
            ],
            Expanded(child: _buildTimeline(theme)),
            const SizedBox(height: AleraTokens.space12),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final workspace = _workspacePath ?? 'No workspace selected';
    final sessionLabel = _sessionId == null
        ? 'No session'
        : 'Session ${_shorten(_sessionId!)}';
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  workspace,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              TextButton(
                onPressed: _starting ? null : _pickWorkspace,
                child: const Text('Choose folder'),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  sessionLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton.icon(
                onPressed: (_starting || _booting) ? null : _startSession,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(
                  _sessionId == null ? 'Start session' : 'New session',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(_PendingApproval approval) {
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Permission requested',
            style: TextStyle(
              color: AleraTokens.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(approval.description),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space8,
            children: <Widget>[
              for (final option in approval.options)
                FilledButton(
                  onPressed: () => _approve(approval, option),
                  child: Text(_approvalOptionLabel(option)),
                ),
              FilledButton(
                onPressed: () => _decline(approval),
                style: FilledButton.styleFrom(
                  backgroundColor: AleraTokens.error,
                  foregroundColor: AleraTokens.onError,
                ),
                child: const Text('Deny'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: _entries.isEmpty
          ? Center(
              child: Text(
                'No events yet. Start a session and send a prompt.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            )
          : ListView.separated(
              controller: _scrollController,
              itemCount: _entries.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AleraTokens.space4),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _buildEntry(entry);
              },
            ),
    );
  }

  Widget _buildEntry(_AcpEntry entry) {
    final isLocal = entry.method == 'local';
    final color = isLocal
        ? AleraTokens.foregroundMuted
        : AleraTokens.foreground;
    final body = isLocal
        ? entry.payload['message']?.toString() ?? ''
        : _formatPayload(entry.payload);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entry.method,
            style: AleraTokens.monoStyle.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
          Text(body, style: AleraTokens.monoStyle.copyWith(color: color)),
        ],
      ),
    );
  }

  String _formatPayload(Map<String, dynamic> payload) {
    try {
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
      return payload.toString();
    }
  }

  Widget _buildComposer() {
    final canSend = _sessionId != null && !_sending;
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _promptController,
            minLines: 1,
            maxLines: 4,
            enabled: canSend,
            decoration: const InputDecoration(
              hintText: 'Type a prompt for the agent',
              border: InputBorder.none,
            ),
            onSubmitted: (_) => canSend ? _sendPrompt() : null,
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton.icon(
                onPressed: _sessionId == null ? null : _cancel,
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('Cancel turn'),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton.icon(
                onPressed: canSend ? _sendPrompt : null,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shorten(String id) {
    if (id.length <= 12) {
      return id;
    }
    return '${id.substring(0, 8)}…';
  }

  String _approvalOptionLabel(String optionId) {
    final words = optionId.replaceAll('_', ' ').trim();
    if (words.isEmpty) {
      return optionId;
    }
    return words[0].toUpperCase() + words.substring(1);
  }
}

class _AcpEntry {
  _AcpEntry({required this.method, required this.payload});

  final String method;
  final Map<String, dynamic> payload;
}

class _PendingApproval {
  _PendingApproval({
    required this.requestId,
    required this.description,
    required this.options,
  });

  final Object requestId;
  final String description;
  final List<String> options;
}
