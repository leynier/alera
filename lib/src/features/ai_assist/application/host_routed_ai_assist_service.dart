import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:uuid/uuid.dart';

/// Resolves the remote workspace that owns a checkout path, or null when the
/// path is local.
typedef AiAssistRemoteWorkspaceResolver = String? Function(String path);

/// The margin the runtime request gets over the generation's own timeout, so
/// the host's "timed out" answer arrives instead of a dropped request.
const Duration _requestMargin = Duration(seconds: 45);

/// [AiAssistService] that generates where the checkout is. A local workspace
/// keeps the desktop implementation; a workspace on another host becomes the
/// `aiText.*` request the runtime forwards to that host, because the agent CLI
/// reads the repository and signs in with that host's credentials. The runtime
/// sends the settings the user configured here along with the request, so the
/// result is the one this machine would have produced.
class HostRoutedAiAssistService implements AiAssistService {
  HostRoutedAiAssistService({
    required this.local,
    required this.client,
    required this.remoteWorkspaceIdFor,
    this.beforeAccess,
    String Function()? newOperationId,
  }) : _newOperationId = newOperationId ?? const Uuid().v4;

  final AiAssistService local;
  final RuntimeHostClient client;
  final AiAssistRemoteWorkspaceResolver remoteWorkspaceIdFor;
  final Future<void> Function()? beforeAccess;
  final String Function() _newOperationId;
  final Map<String, String> _operations = <String, String>{};
  final Set<String> _canceled = <String>{};

  @override
  Future<AiAssistResult> generate(AiAssistRequest request) async {
    final workspaceId = remoteWorkspaceIdFor(request.workspacePath);
    if (workspaceId == null) {
      return local.generate(request);
    }
    if (!request.settings.enabled) {
      throw const AiAssistException('AI Assist is disabled.');
    }
    final verb = _verbFor(request.operation);
    final key = _laneKey(request.workspacePath, request.operation);
    if (_operations.containsKey(key)) {
      throw const AiAssistException('Generation is already running.');
    }
    final operationId = _newOperationId();
    _operations[key] = operationId;
    _canceled.remove(key);
    try {
      await beforeAccess?.call();
      final value = await client.runtimeRequest(verb, <String, Object?>{
        'operationId': operationId,
        'workspaceId': workspaceId,
        if (request.operation == AiAssistOperation.pullRequestDetails)
          'baseBranch': request.baseBranch?.trim() ?? '',
      }, Duration(seconds: request.settings.timeoutSeconds) + _requestMargin);
      if (_canceled.contains(key)) {
        throw const AiAssistCanceledException();
      }
      return _resultFor(request.operation, value);
    } on AiAssistException {
      rethrow;
    } catch (error) {
      if (_canceled.contains(key)) {
        throw const AiAssistCanceledException();
      }
      throw AiAssistException(error.toString());
    } finally {
      _operations.remove(key);
      _canceled.remove(key);
    }
  }

  @override
  void cancel(String workspacePath, AiAssistOperation operation) {
    if (remoteWorkspaceIdFor(workspacePath) == null) {
      local.cancel(workspacePath, operation);
      return;
    }
    final key = _laneKey(workspacePath, operation);
    final operationId = _operations[key];
    if (operationId == null) {
      return;
    }
    _canceled.add(key);
    client.runtimeRequest('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    }).ignore();
  }

  static String _verbFor(AiAssistOperation operation) => switch (operation) {
    AiAssistOperation.commitMessage => 'aiText.commitMessage.generate',
    AiAssistOperation.pullRequestDetails =>
      'aiText.pullRequestDetails.generate',
    _ => throw AiAssistException(
      '${operation.label} generation is not wired yet.',
    ),
  };

  static AiAssistResult _resultFor(AiAssistOperation operation, Object? value) {
    if (value is! Map) {
      throw const AiAssistException('The workspace host returned no text.');
    }
    final label = value['agentLabel']?.toString() ?? '';
    final String text;
    if (operation == AiAssistOperation.pullRequestDetails) {
      // Callers parse the first line as the title and the rest as the body.
      final title = value['title']?.toString().trim() ?? '';
      final body = value['body']?.toString().trim() ?? '';
      text = body.isEmpty ? title : '$title\n\n$body';
    } else {
      text = value['message']?.toString().trim() ?? '';
    }
    if (text.isEmpty) {
      throw const AiAssistException('The workspace host returned no text.');
    }
    return AiAssistResult(text: text, agentLabel: label);
  }

  static String _laneKey(String workspacePath, AiAssistOperation operation) {
    return '$workspacePath::${operation.key}';
  }
}
