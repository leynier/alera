import 'dart:async';

import 'package:alera/src/features/projects/application/chat_repository.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_controller.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/application/worktree_service.dart';
import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectsController pinned chats', () {
    test(
      'does not prune pins from projects whose chats have not loaded',
      () async {
        final harness = _ProjectsControllerHarness();
        final controller = harness.buildController();
        addTearDown(() async {
          controller.dispose();
          await harness.dispose();
        });

        await controller.bootstrap();
        controller
          ..togglePinned('p1-chat')
          ..togglePinned('p2-chat');

        harness.emitChats('p1', <ChatSummary>[
          _chat(id: 'p1-chat', projectId: 'p1'),
        ]);
        await _flushEvents();

        expect(controller.state.pinnedChatIds, <String>{'p1-chat', 'p2-chat'});
        expect(controller.state.pinnedChatOrder, <String>[
          'p1-chat',
          'p2-chat',
        ]);
      },
    );

    test('prunes stale pins after all project chats have loaded', () async {
      final harness = _ProjectsControllerHarness();
      final controller = harness.buildController();
      addTearDown(() async {
        controller.dispose();
        await harness.dispose();
      });

      await controller.bootstrap();
      controller
        ..togglePinned('p1-chat')
        ..togglePinned('ghost-chat')
        ..togglePinned('p2-chat');

      harness.emitChats('p1', <ChatSummary>[
        _chat(id: 'p1-chat', projectId: 'p1'),
      ]);
      await _flushEvents();
      harness.emitChats('p2', <ChatSummary>[
        _chat(id: 'p2-chat', projectId: 'p2'),
      ]);
      await _flushEvents();

      expect(controller.state.pinnedChatIds, <String>{'p1-chat', 'p2-chat'});
      expect(controller.state.pinnedChatOrder, <String>['p1-chat', 'p2-chat']);
    });
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

ChatSummary _chat({required String id, required String projectId}) {
  final now = DateTime(2026, 5, 16);
  return ChatSummary(
    id: id,
    projectId: projectId,
    title: id,
    model: 'gpt-test',
    createdAt: now,
    updatedAt: now,
  );
}

class _ProjectsControllerHarness {
  _ProjectsControllerHarness() {
    final now = DateTime(2026, 5, 16);
    projects = <Project>[
      Project(
        id: 'p1',
        name: 'Project one',
        repoPath: '/tmp/p1',
        createdAt: now,
        updatedAt: now,
      ),
      Project(
        id: 'p2',
        name: 'Project two',
        repoPath: '/tmp/p2',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    projectRepository = _FakeProjectRepository(projects);
    chatRepository = _FakeChatRepository();
  }

  late final List<Project> projects;
  late final _FakeProjectRepository projectRepository;
  late final _FakeChatRepository chatRepository;

  ProjectsController buildController() {
    final processRunner = _FakeProcessRunner();
    final service = ProjectsService(
      projectService: ProjectService(processRunner),
      projectRepository: projectRepository,
      chatRepository: chatRepository,
      worktreeService: WorktreeService(
        projectRepository: projectRepository,
        processRunner: processRunner,
      ),
    );
    return ProjectsController(projectsService: service);
  }

  void emitChats(String projectId, List<ChatSummary> chats) {
    chatRepository.emit(projectId, chats);
  }

  Future<void> dispose() async {
    await projectRepository.dispose();
    await chatRepository.dispose();
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this._projects);

  final List<Project> _projects;
  final StreamController<List<Project>> _projectsController =
      StreamController<List<Project>>.broadcast();
  final Map<String, StreamController<List<Worktree>>> _worktreeControllers =
      <String, StreamController<List<Worktree>>>{};

  @override
  Future<List<Project>> listAll() async => _projects;

  @override
  Stream<List<Project>> watchAll() => _projectsController.stream;

  @override
  Stream<List<Worktree>> watchWorktrees(String projectId) =>
      _worktreeControllers
          .putIfAbsent(
            projectId,
            () => StreamController<List<Worktree>>.broadcast(),
          )
          .stream;

  Future<void> dispose() async {
    await _projectsController.close();
    for (final controller in _worktreeControllers.values) {
      await controller.close();
    }
  }

  @override
  Future<Project> add(Project project) => throw UnimplementedError();

  @override
  Future<Worktree> addWorktree(Worktree worktree) => throw UnimplementedError();

  @override
  Future<Worktree?> findWorktreeById(String worktreeId) =>
      throw UnimplementedError();

  @override
  Future<List<Worktree>> listWorktrees(String projectId) =>
      throw UnimplementedError();

  @override
  Future<void> remove(String projectId) => throw UnimplementedError();

  @override
  Future<Project> update(Project project) => throw UnimplementedError();

  @override
  Future<Worktree> updateWorktree(Worktree worktree) =>
      throw UnimplementedError();
}

class _FakeChatRepository implements ChatRepository {
  final Map<String, StreamController<List<ChatSummary>>> _controllers =
      <String, StreamController<List<ChatSummary>>>{};

  @override
  Stream<List<ChatSummary>> watchByProject(String projectId) => _controllers
      .putIfAbsent(
        projectId,
        () => StreamController<List<ChatSummary>>.broadcast(),
      )
      .stream;

  void emit(String projectId, List<ChatSummary> chats) {
    _controllers[projectId]?.add(chats);
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }

  @override
  Future<ChatMessage> appendMessage(ChatMessage message) =>
      throw UnimplementedError();

  @override
  Future<ChatSummary?> findById(String chatId) => throw UnimplementedError();

  @override
  Future<List<ChatSummary>> listByProject(String projectId) =>
      throw UnimplementedError();

  @override
  Future<List<TimelineCell>> loadCells(String chatId) =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> loadMessages(String chatId) =>
      throw UnimplementedError();

  @override
  Future<int> nextSeq(String chatId) => throw UnimplementedError();

  @override
  Future<void> remove(String chatId, {bool cascadeMessages = true}) =>
      throw UnimplementedError();

  @override
  Future<void> replaceCells(String chatId, List<TimelineCell> cells) =>
      throw UnimplementedError();

  @override
  Future<ChatSummary> upsert(ChatSummary chat) => throw UnimplementedError();
}

class _FakeProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
