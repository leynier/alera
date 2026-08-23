part of 'codex_chat_surface.dart';

enum _TypedSessionCommandKind {
  goal('goal'),
  rename('rename'),
  newThread('new'),
  clear('clear'),
  resume('resume');

  const _TypedSessionCommandKind(this.token);

  final String token;
}

final class _TypedSessionCommand {
  const _TypedSessionCommand({required this.kind, required this.argument});

  static final RegExp _pattern = RegExp(
    r'^/(goal|rename|new|clear|resume)(?:\s+(.+))?$',
    caseSensitive: false,
  );

  final _TypedSessionCommandKind kind;
  final String? argument;

  bool get hasArgument => argument != null && argument!.isNotEmpty;

  static _TypedSessionCommand? parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final token = match.group(1)!.toLowerCase();
    return _TypedSessionCommand(
      kind: _TypedSessionCommandKind.values.firstWhere(
        (kind) => kind.token == token,
      ),
      argument: match.group(2)?.trim(),
    );
  }
}

extension _CodexTypedSessionCommands on _CodexChatSurfaceState {
  Future<bool> _dispatchTypedSessionCommand(
    CodexChatController controller,
    CodexChatState state,
    _TypedSessionCommand command,
  ) => switch (command.kind) {
    _TypedSessionCommandKind.goal => _runTypedGoalCommand(
      controller,
      state,
      command,
    ),
    _TypedSessionCommandKind.rename => _runTypedRenameCommand(
      controller,
      command,
    ),
    _TypedSessionCommandKind.newThread => _runTypedThreadResetCommand(
      controller,
      state,
      command,
      controller.newThread,
    ),
    _TypedSessionCommandKind.clear => _runTypedThreadResetCommand(
      controller,
      state,
      command,
      controller.clearThread,
    ),
    _TypedSessionCommandKind.resume => _runTypedResumeCommand(
      controller,
      state,
      command,
    ),
  };

  Future<bool> _runTypedGoalCommand(
    CodexChatController controller,
    CodexChatState state,
    _TypedSessionCommand command,
  ) async {
    if (!state.supportsGoals) return true;
    _composer.clear();
    await _executeTypedGoalCommand(controller, state, command);
    return true;
  }

  Future<void> _executeTypedGoalCommand(
    CodexChatController controller,
    CodexChatState state,
    _TypedSessionCommand command,
  ) async {
    switch (command.argument?.toLowerCase()) {
      case 'pause':
        await controller.updateGoalStatus(CodexThreadGoalStatus.paused);
      case 'resume':
        await controller.updateGoalStatus(CodexThreadGoalStatus.active);
      case 'clear':
        await controller.clearGoal();
      case 'edit':
        final goal = state.snapshot.goal;
        if (goal != null) {
          final edited = await _showCodexGoalEditor(
            context,
            initialObjective: goal.objective,
          );
          if (edited != null) await controller.editGoal(edited);
        }
      default:
        await _setGoalFromTypedCommand(controller, state, command.argument);
    }
  }

  Future<void> _setGoalFromTypedCommand(
    CodexChatController controller,
    CodexChatState state,
    String? argument,
  ) async {
    if (argument != null && argument.isNotEmpty) {
      await controller.replaceGoal(argument, recordUserMessage: true);
      return;
    }
    final edited = await _showCodexGoalEditor(
      context,
      initialObjective: state.snapshot.goal?.objective ?? '',
    );
    if (edited == null) return;
    if (state.snapshot.goal == null) {
      await controller.setGoal(edited, recordUserMessage: true);
    } else {
      await controller.editGoal(edited);
    }
  }

  Future<bool> _runTypedRenameCommand(
    CodexChatController controller,
    _TypedSessionCommand command,
  ) async {
    _composer.clear();
    if (command.hasArgument) {
      await controller.rename(command.argument!);
    } else {
      await _rename(context, controller);
    }
    return true;
  }

  Future<bool> _runTypedThreadResetCommand(
    CodexChatController controller,
    CodexChatState state,
    _TypedSessionCommand command,
    Future<bool> Function() reset,
  ) async {
    _composer.clear();
    if (!state.supportsSessions) {
      await _openLegacyCodexTab();
      return true;
    }
    final succeeded = await reset();
    final result = _handleTypedThreadResetResult(
      controller,
      command,
      succeeded,
    );
    if (result != null) await result;
    return true;
  }

  Future<void>? _handleTypedThreadResetResult(
    CodexChatController controller,
    _TypedSessionCommand command,
    bool succeeded,
  ) => succeeded && command.hasArgument
      ? controller.rename(command.argument!)
      : null;

  Future<bool> _runTypedResumeCommand(
    CodexChatController controller,
    CodexChatState state,
    _TypedSessionCommand command,
  ) async {
    if (!state.supportsSessions || command.hasArgument) return false;
    _composer.clear();
    await _resumeThread(context, controller, state);
    return true;
  }
}
