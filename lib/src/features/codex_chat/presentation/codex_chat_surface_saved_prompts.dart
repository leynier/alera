part of 'codex_chat_surface.dart';

extension _CodexSavedPrompts on _CodexChatSurfaceState {
  Future<void> _loadSavedPrompts(String workspacePath) async {
    final generation = ++_savedPromptLoadGeneration;
    try {
      final prompts = await _workspaceFiles.listCodexSavedPrompts(
        workspacePath: workspacePath,
      );
      if (!mounted || generation != _savedPromptLoadGeneration) return;
      _setSurfaceState(() => _savedPrompts = prompts);
    } catch (_) {
      if (mounted && generation == _savedPromptLoadGeneration) {
        _setSurfaceState(() => _savedPrompts = const []);
      }
    }
  }

  String _expandSavedPrompt(String input) {
    final match = RegExp(
      r'^/([^\s]+)(?:\s+(.*))?$',
      dotAll: true,
    ).firstMatch(input.trim());
    if (match == null) return input;
    final name = match.group(1)!.toLowerCase();
    native.CodexSavedPrompt? prompt;
    for (final candidate in _savedPrompts) {
      if (candidate.name.toLowerCase() == name) {
        prompt = candidate;
        break;
      }
    }
    if (prompt == null) return input;
    final rawArguments = match.group(2)?.trim() ?? '';
    return expandCodexSavedPrompt(prompt.body, rawArguments);
  }
}
