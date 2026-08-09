import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

final class FakeMobileCodexClient
    implements MobileCodexClient, MobileCodexWorkspaceClient {
  FakeMobileCodexClient({
    this.timelineCells,
    this.initialSnapshot,
    this.initialThreadId,
    this.responses = const <String, Map<String, Object?>>{},
    this.responseErrors = const <String, Object>{},
    this.requestHandler,
    this.workspaceFiles = const [],
    this.workspaceQuickOpenStart,
    this.workspaceQuickOpenStarter,
    this.workspaceQuickOpenSearcher,
    this.workspaceQuickOpenStopper,
    this.savedPrompts = const <MobileCodexSavedPrompt>[],
    this.savedPromptsLoader,
    this.workspaceFileReader,
    this.promptAttachmentReader,
    this.promptAttachmentReadSupported = false,
    this.configuration,
    this.recovery,
    this.supportsCodexSessions = true,
    this.supportsCodexTurnPolicy = true,
  });

  final List<Object?>? timelineCells;
  final Map<String, Object?>? initialSnapshot;
  final String? initialThreadId;
  final Map<String, Map<String, Object?>> responses;
  final Map<String, Object> responseErrors;
  final Future<Map<String, Object?>>? Function(
    String type,
    Map<String, Object?> payload,
  )?
  requestHandler;
  final List<String> workspaceFiles;
  final Future<MobileWorkspaceQuickOpenSession>? workspaceQuickOpenStart;
  final Future<MobileWorkspaceQuickOpenSession> Function(
    String workspaceId,
    String? cwd,
  )?
  workspaceQuickOpenStarter;
  final Future<List<MobileWorkspaceQuickOpenMatch>> Function(
    MobileWorkspaceQuickOpenSession session,
    String query,
    int limit,
  )?
  workspaceQuickOpenSearcher;
  final Future<void> Function(MobileWorkspaceQuickOpenSession session)?
  workspaceQuickOpenStopper;
  final List<MobileCodexSavedPrompt> savedPrompts;
  final Future<List<MobileCodexSavedPrompt>> Function(
    String workspaceId,
    String? cwd,
  )?
  savedPromptsLoader;
  final Future<MobileWorkspaceFileRange> Function(
    String workspaceId,
    String relativePath,
    String? cwd,
    int offset,
    int length,
  )?
  workspaceFileReader;
  final Future<MobileWorkspaceFileRange> Function(
    String path,
    int offset,
    int length,
  )?
  promptAttachmentReader;
  final bool promptAttachmentReadSupported;
  Map<String, Object?>? configuration;
  Map<String, Object?>? recovery;
  @override
  final bool supportsCodexSessions;
  @override
  final bool supportsCodexTurnPolicy;
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<MobileCodexCall> calls = <MobileCodexCall>[];
  final List<MobileWorkspaceQuickOpenSession> stoppedQuickOpenSessions =
      <MobileWorkspaceQuickOpenSession>[];
  final List<MobileWorkspaceQuickOpenSession> searchedQuickOpenSessions =
      <MobileWorkspaceQuickOpenSession>[];
  var quickOpenSearchCount = 0;
  String? lastSavedPromptWorkspaceId;
  String? lastSavedPromptCwd;

  @override
  bool get supportsCodexChat => true;

  @override
  bool get supportsCodexWorkspaceFiles => workspaceFiles.isNotEmpty;

  @override
  bool get supportsPromptFileUpload => false;

  @override
  bool get supportsPromptAttachmentRead => promptAttachmentReadSupported;

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Future<Never> createCodexTab(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, Object?>> codexRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    calls.add(MobileCodexCall(type, payload));
    final responseError = responseErrors[type];
    if (responseError != null) throw responseError;
    final handled = requestHandler?.call(type, payload);
    if (handled != null) return handled;
    if (type == 'codex.thread.open') {
      return <String, Object?>{
        'threadId': initialThreadId,
        'snapshot':
            initialSnapshot ??
            <String, Object?>{
              'timelineCells': timelineCells ?? _defaultTimeline,
              'pendingRequests': _pendingRequests,
            },
        'configuration': configuration,
        'recovery': recovery,
      };
    }
    final response = responses[type];
    if (response != null) return Map<String, Object?>.from(response);
    if (type == 'codex.tab.configure') {
      configuration = Map<String, Object?>.from(
        payload['configuration']! as Map,
      );
      return <String, Object?>{'configuration': configuration};
    }
    if (type == 'codex.thread.recover') {
      recovery = null;
      return <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': timelineCells ?? _defaultTimeline,
          'pendingRequests': const <Object?>[],
        },
        'configuration': configuration,
      };
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-current',
            'displayName': 'Current Codex',
            'isDefault': true,
            'contextWindowTokens': 128000,
            'supportedReasoningEfforts': <Object?>[
              <String, Object?>{'reasoningEffort': 'xhigh'},
              <String, Object?>{'reasoningEffort': 'low'},
            ],
            'defaultReasoningEffort': 'low',
            'additionalSpeedTiers': <String>['fast'],
            'serviceTiers': <Object?>[
              <String, Object?>{'id': 'priority', 'name': 'Fast'},
            ],
          },
        ],
      };
    }
    if (type == 'codex.skills.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'review', 'path': '/skills/review'},
        ],
      };
    }
    if (type == 'codex.apps.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'name': 'filesystem',
            'slug': 'filesystem',
            'id': 'connector-filesystem',
            'connectorId': 'connector-filesystem',
          },
        ],
      };
    }
    if (type == 'codex.collaborationModes.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'mode': 'plan'},
        ],
      };
    }
    return <String, Object?>{};
  }

  @override
  Future<MobileWorkspaceQuickOpenSession> startWorkspaceQuickOpen(
    String workspaceId, {
    String? cwd,
  }) async =>
      workspaceQuickOpenStarter?.call(workspaceId, cwd) ??
      workspaceQuickOpenStart ??
      MobileWorkspaceQuickOpenSession(
        id: 'quick-open-$workspaceId',
        indexedFileCount: workspaceFiles.length,
      );

  @override
  Future<List<MobileWorkspaceQuickOpenMatch>> searchWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
    String query, {
    int limit = 20,
  }) async {
    quickOpenSearchCount += 1;
    searchedQuickOpenSessions.add(session);
    final searcher = workspaceQuickOpenSearcher;
    if (searcher != null) return searcher(session, query, limit);
    return workspaceFiles
        .where((path) => path.toLowerCase().contains(query.toLowerCase()))
        .take(limit)
        .map(
          (path) => MobileWorkspaceQuickOpenMatch(relativePath: path, score: 1),
        )
        .toList(growable: false);
  }

  @override
  Future<void> stopWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
  ) async {
    final stopper = workspaceQuickOpenStopper;
    if (stopper != null) return stopper(session);
    stoppedQuickOpenSessions.add(session);
  }

  @override
  Future<List<MobileCodexSavedPrompt>> listCodexSavedPrompts(
    String workspaceId, {
    String? cwd,
  }) async {
    lastSavedPromptWorkspaceId = workspaceId;
    lastSavedPromptCwd = cwd;
    final loader = savedPromptsLoader;
    if (loader != null) return loader(workspaceId, cwd);
    return savedPrompts;
  }

  @override
  Future<MobileWorkspaceFileRange> readWorkspaceFile({
    required String workspaceId,
    required String relativePath,
    String? cwd,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async {
    final reader = workspaceFileReader;
    if (reader == null) throw UnimplementedError();
    return reader(workspaceId, relativePath, cwd, offset, length);
  }

  @override
  Future<MobileWorkspaceFileRange> readPromptAttachment({
    required String path,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async {
    final reader = promptAttachmentReader;
    if (reader == null) throw UnimplementedError();
    return reader(path, offset, length);
  }

  @override
  Future<PromptFileUploadResult> uploadPromptFile({
    required String name,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async => throw UnimplementedError();

  void emit(MobileRuntimeEvent event) => _events.add(event);

  void dispose() => _events.close();
}

final class MobileCodexCall {
  const MobileCodexCall(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}

const List<Object?> _defaultTimeline = <Object?>[
  <String, Object?>{
    'id': 'request',
    'kind': 'userMessage',
    'status': 'completed',
    'markdownText': 'Inspect the workspace',
  },
  <String, Object?>{
    'id': 'answer',
    'kind': 'assistantMessage',
    'status': 'completed',
    'markdownText': 'Answer from Codex',
  },
  <String, Object?>{
    'id': 'plan',
    'kind': 'plan',
    'status': 'completed',
    'markdownText': '1. Inspect\n2. Implement',
  },
];

const List<Object?> _pendingRequests = <Object?>[
  <String, Object?>{
    'id': 9,
    'method': 'item/tool/request_user_input',
    'params': <String, Object?>{
      'questions': <Object?>[
        <String, Object?>{
          'id': 'mode',
          'question': 'Choose a mode',
          'isOther': true,
          'options': <Object?>[
            <String, Object?>{'label': 'Fast'},
            <String, Object?>{'label': 'Careful'},
          ],
        },
      ],
    },
  },
  <String, Object?>{
    'id': 10,
    'method': 'item/commandExecution/requestApproval',
    'params': <String, Object?>{'command': 'git status'},
  },
  <String, Object?>{
    'id': 11,
    'method': 'mcpServer/elicitation/request',
    'params': <String, Object?>{
      'mode': 'form',
      'requestedSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
];
