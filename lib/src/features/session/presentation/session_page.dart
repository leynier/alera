import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/terminal/presentation/terminal_panel.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({super.key});

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  final _projectController = TextEditingController();
  final _promptController = TextEditingController();
  final _baseBranchController = TextEditingController();
  final _plannerModelController = TextEditingController(text: 'gpt-5');
  final _executorModelController = TextEditingController(text: 'gpt-5-codex');
  final _inputController = TextEditingController();
  final _mcpIdController = TextEditingController();
  final _mcpCommandController = TextEditingController();

  final Map<Object, AllowScope> _approvalScopes = <Object, AllowScope>{};

  SessionWorkspaceMode _workspaceMode = SessionWorkspaceMode.repository;
  ExecutionMode _executionMode = ExecutionMode.normal;
  var _autoPull = false;
  var _fullAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(sessionControllerProvider.notifier);
      final defaults = await controller.loadSettingsDefaults();
      if (!mounted) {
        return;
      }
      setState(() {
        _plannerModelController.text = defaults.plannerModel;
        _executorModelController.text = defaults.executorModel;
      });
    });
  }

  @override
  void dispose() {
    _projectController.dispose();
    _promptController.dispose();
    _baseBranchController.dispose();
    _plannerModelController.dispose();
    _executorModelController.dispose();
    _inputController.dispose();
    _mcpIdController.dispose();
    _mcpCommandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alera'),
        actions: <Widget>[
          if (state.activeSession != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  state.activeSession?.worktreeSpec != null
                      ? 'worktree session'
                      : 'repository session',
                ),
              ),
            ),
        ],
      ),
      body: Row(
        children: <Widget>[
          SizedBox(
            width: 430,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildSessionForm(state, controller),
                const SizedBox(height: 16),
                _buildSessionActions(state, controller),
                const SizedBox(height: 16),
                _buildApprovals(state, controller),
                const SizedBox(height: 16),
                _buildMcpPanel(state, controller),
                if (state.lastOauthUrl != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText('oauth url: ${state.lastOauthUrl}'),
                ],
                if (state.error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    state.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: state.terminalSession == null
                      ? const Center(
                          child: Text('start a session to open terminal'),
                        )
                      : TerminalPanel(session: state.terminalSession!),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          decoration: const InputDecoration(
                            hintText: 'message or slash command (/review, /init)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: state.activeSession == null || state.isBusy
                            ? null
                            : () {
                                final text = _inputController.text.trim();
                                if (text.isEmpty) {
                                  return;
                                }
                                _inputController.clear();
                                controller.sendInput(text);
                              },
                        child: const Text('send'),
                      ),
                    ],
                  ),
                ),
                _buildActivityLog(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionForm(SessionState state, SessionController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('session setup', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _projectController,
          decoration: const InputDecoration(labelText: 'project path'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          decoration: const InputDecoration(labelText: 'first prompt'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SessionWorkspaceMode>(
          initialValue: _workspaceMode,
          decoration: const InputDecoration(labelText: 'workspace mode'),
          items: SessionWorkspaceMode.values
              .map(
                (mode) => DropdownMenuItem<SessionWorkspaceMode>(
                  value: mode,
                  child: Text(mode.name),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) {
              setState(() => _workspaceMode = value);
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ExecutionMode>(
          initialValue: _executionMode,
          decoration: const InputDecoration(labelText: 'execution mode'),
          items: ExecutionMode.values
              .map(
                (mode) => DropdownMenuItem<ExecutionMode>(
                  value: mode,
                  child: Text(mode.name),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) {
              setState(() => _executionMode = value);
            }
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _plannerModelController,
          decoration: const InputDecoration(labelText: 'planner model'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _executorModelController,
          decoration: const InputDecoration(labelText: 'executor model'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _baseBranchController,
          decoration: const InputDecoration(labelText: 'base branch (optional)'),
        ),
        SwitchListTile(
          title: const Text('auto pull base branch'),
          value: _autoPull,
          onChanged: (value) => setState(() => _autoPull = value),
        ),
        SwitchListTile(
          title: const Text('full access (normal mode only)'),
          value: _fullAccess,
          onChanged: (value) => setState(() => _fullAccess = value),
        ),
        FilledButton(
          onPressed: state.isBusy
              ? null
              : () {
                  controller.createSession(
                    SessionCreateRequest(
                      projectPath: _projectController.text.trim(),
                      workspaceMode: _workspaceMode,
                      baseBranch: _baseBranchController.text.trim().isEmpty
                          ? null
                          : _baseBranchController.text.trim(),
                      autoPullBaseBranch: _autoPull,
                      firstPrompt: _promptController.text.trim(),
                      fullAccess: _fullAccess,
                      executionMode: _executionMode,
                      plannerModel: _plannerModelController.text.trim(),
                      executorModel: _executorModelController.text.trim(),
                    ),
                  );
                },
          child: const Text('start session'),
        ),
      ],
    );
  }

  Widget _buildSessionActions(SessionState state, SessionController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('session actions', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: state.activeSession == null || state.isBusy
              ? null
              : () => controller.promoteActiveToWorktree(),
          child: const Text('promote to worktree'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: state.activeSession == null || state.isBusy
              ? null
              : () => _closeSessionWithPrompt(state, controller),
          child: const Text('close session'),
        ),
      ],
    );
  }

  Widget _buildApprovals(SessionState state, SessionController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('pending approvals', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('${state.pendingApprovals.length}'),
          ],
        ),
        const SizedBox(height: 8),
        if (state.pendingApprovals.isEmpty)
          const Text('no pending approvals')
        else
          ...state.pendingApprovals.map((approval) {
            final currentScope =
                _approvalScopes[approval.requestId] ?? AllowScope.session;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${approval.itemType.name} - ${approval.itemId}'),
                    if (approval.command != null) Text('command: ${approval.command}'),
                    if (approval.cwd != null) Text('cwd: ${approval.cwd}'),
                    if (approval.reason != null) Text('reason: ${approval.reason}'),
                    if (approval.itemType == ApprovalItemType.commandExecution) ...<Widget>[
                      const SizedBox(height: 8),
                      DropdownButton<AllowScope>(
                        value: currentScope,
                        items: AllowScope.values
                            .map(
                              (scope) => DropdownMenuItem<AllowScope>(
                                value: scope,
                                child: Text('allow scope: ${scope.name}'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _approvalScopes[approval.requestId] = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        FilledButton(
                          onPressed: () {
                            controller.decideApproval(
                              approval: approval,
                              decision: ApprovalDecisionType.accept,
                              allowScope: approval.itemType == ApprovalItemType.commandExecution
                                  ? currentScope
                                  : null,
                            );
                          },
                          child: const Text('accept'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () {
                            controller.decideApproval(
                              approval: approval,
                              decision: ApprovalDecisionType.decline,
                            );
                          },
                          child: const Text('decline'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMcpPanel(SessionState state, SessionController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('mcp', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: () => controller.loadMcpServers(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        TextField(
          controller: _mcpIdController,
          decoration: const InputDecoration(labelText: 'server id'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mcpCommandController,
          decoration: const InputDecoration(labelText: 'command'),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: state.isBusy
                  ? null
                  : () {
                      controller.addMcpServer(
                        id: _mcpIdController.text.trim(),
                        command: _mcpCommandController.text.trim(),
                      );
                    },
              child: const Text('add/update'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: state.isBusy
                  ? null
                  : () => controller.removeMcpServer(_mcpIdController.text.trim()),
              child: const Text('remove'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: state.isBusy
                  ? null
                  : () => controller.loginMcpServer(_mcpIdController.text.trim()),
              child: const Text('oauth login'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...state.mcpServers.map(
          (server) => ListTile(
            dense: true,
            title: Text(server.id),
            subtitle: Text(server.transport),
            trailing: Text(server.enabled ? 'enabled' : 'disabled'),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityLog(SessionState state) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: state.activityLog.length,
        itemBuilder: (context, index) {
          final logIndex = state.activityLog.length - 1 - index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              state.activityLog[logIndex],
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }

  Future<void> _closeSessionWithPrompt(
    SessionState state,
    SessionController controller,
  ) async {
    final activeSession = state.activeSession;
    if (activeSession == null) {
      return;
    }

    var removeWorktree = false;
    if (activeSession.worktreeSpec != null) {
      final decision = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('close worktree session'),
            content: const Text('do you want to remove the worktree when closing this session?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('keep worktree'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('remove worktree'),
              ),
            ],
          );
        },
      );
      removeWorktree = decision ?? false;
    }

    await controller.closeActiveSession(removeWorktree: removeWorktree);
  }
}
