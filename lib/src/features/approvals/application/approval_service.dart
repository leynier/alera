import 'dart:convert';

import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:alera/src/shared/models/contracts.dart';

class ApprovalService {
  ApprovalService({required StringStore preferencesStore})
      : _preferencesStore = preferencesStore;

  final StringStore _preferencesStore;

  static const String _globalAllowlistKey = 'allowlist.global';

  final Map<String, Set<String>> _sessionAllowlist = <String, Set<String>>{};
  final Map<String, Set<String>> _projectAllowlist = <String, Set<String>>{};

  Future<CommandApprovalDecision> evaluate({
    required String sessionId,
    required String projectPath,
    required CommandApprovalRequest request,
    required ApprovalPolicy policy,
  }) async {
    if (_isBlockedByPlanMode(request)) {
      return const CommandApprovalDecision(
        approved: false,
        reason: 'plan mode does not allow filesystem writes',
      );
    }

    if (request.fullAccess && request.mode == ExecutionMode.normal) {
      return const CommandApprovalDecision(
        approved: true,
        reason: 'full access enabled',
      );
    }

    final normalizedCommand = _normalizeCommand(request.command);

    if (_matches(_sessionAllowlist[sessionId], normalizedCommand)) {
      return const CommandApprovalDecision(
        approved: true,
        allowScope: AllowScope.session,
      );
    }

    if (_matches(_projectAllowlist[projectPath], normalizedCommand)) {
      return const CommandApprovalDecision(
        approved: true,
        allowScope: AllowScope.project,
      );
    }

    final globalAllowlist = await _readGlobalAllowlist();
    if (_matches(globalAllowlist, normalizedCommand)) {
      return const CommandApprovalDecision(
        approved: true,
        allowScope: AllowScope.global,
      );
    }

    if (policy == ApprovalPolicy.denyAll) {
      return const CommandApprovalDecision(
        approved: false,
        reason: 'denied by approval policy',
      );
    }

    return const CommandApprovalDecision(approved: false);
  }

  Future<void> allowCommand({
    required AllowScope scope,
    required String commandPattern,
    required String sessionId,
    required String projectPath,
  }) async {
    final normalized = _normalizeCommand(commandPattern);
    if (scope == AllowScope.session) {
      _sessionAllowlist.putIfAbsent(sessionId, () => <String>{}).add(normalized);
      return;
    }

    if (scope == AllowScope.project) {
      _projectAllowlist.putIfAbsent(projectPath, () => <String>{}).add(normalized);
      return;
    }

    final current = await _readGlobalAllowlist();
    current.add(normalized);
    await _preferencesStore.setString(
      _globalAllowlistKey,
      jsonEncode(current.toList()),
    );
  }

  bool _isBlockedByPlanMode(CommandApprovalRequest request) {
    if (request.mode != ExecutionMode.plan) {
      return false;
    }

    if (request.actions.contains(CommandAction.filesystemWrite)) {
      return true;
    }

    final writeRegex = RegExp(
      r'\b(rm|mv|cp|tee|cat\s+>|echo\s+.*>|sed\s+-i|perl\s+-i|truncate|chmod|chown|git\s+add|git\s+commit|git\s+push)\b',
      caseSensitive: false,
    );

    return writeRegex.hasMatch(request.command);
  }

  bool _matches(Set<String>? patterns, String command) {
    if (patterns == null || patterns.isEmpty) {
      return false;
    }

    for (final pattern in patterns) {
      if (command == pattern || command.startsWith('$pattern ')) {
        return true;
      }
    }

    return false;
  }

  String _normalizeCommand(String command) {
    return command.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Set<String>> _readGlobalAllowlist() async {
    final raw = await _preferencesStore.getString(_globalAllowlistKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <String>{};
    }

    return decoded.whereType<String>().map(_normalizeCommand).toSet();
  }
}
