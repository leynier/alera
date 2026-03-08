import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeProjectService implements ProjectService {
  @override
  Future<bool> isGitRepository(String path) async => true;

  @override
  Future<ProjectValidationResult> validateGitRepository(String path) async {
    return ProjectValidationResult.ok();
  }

  @override
  Future<List<String>> listGitBranches(String path) async {
    return const <String>['main'];
  }
}

Future<SessionService> _startSessionService() async {
  final script = p.absolute(
    'test/integration/fixtures/fake_codex_app_server.dart',
  );
  final client = CodexAppServerClient(
    processRunner: const IoProcessRunner(),
    executable: 'dart',
    arguments: <String>[script],
  );
  final orchestrator = AgentOrchestrator(client);
  return SessionService(
    orchestrator: orchestrator,
    projectService: _FakeProjectService(),
  );
}

void main() {
  group('SessionService integration', () {
    test('renameSessionThread updates the local session title', () async {
      final service = await _startSessionService();
      addTearDown(service.shutdown);

      final session = await service.createSession(
        const SessionCreateRequest(
          projectPath: '/tmp/project',
          firstPrompt: 'Inspect the repo',
          model: 'gpt-5.2-codex',
        ),
      );

      await service.renameSessionThread(
        sessionId: session.id,
        name: 'Repository review',
      );

      final updated = service.sessions.singleWhere(
        (item) => item.id == session.id,
      );
      expect(updated.title, 'Repository review');
    });

    test(
      'review and list wrappers return typed results for a session',
      () async {
        final service = await _startSessionService();
        addTearDown(service.shutdown);

        final session = await service.createSession(
          const SessionCreateRequest(
            projectPath: '/tmp/project',
            firstPrompt: 'Inspect the repo',
            model: 'gpt-5.2-codex',
          ),
        );

        final collaborationModes = await service.listCollaborationModes();
        expect(collaborationModes, isNotEmpty);
        expect(collaborationModes.first.name, 'default');

        final skills = await service.listSkills(
          cwds: const <String>['/tmp/project'],
          perCwdExtraUserRoots: const <CodexSkillsListExtraRootsForCwd>[
            CodexSkillsListExtraRootsForCwd(
              cwd: '/tmp/project',
              extraUserRoots: <String>['/tmp/shared-skills'],
            ),
          ],
        );
        expect(skills.single.skills, isNotEmpty);

        final apps = await service.listApps(sessionId: session.id, limit: 1);
        expect(apps.data.single.labels?['threadId'], session.threadId);

        final review = await service.startReview(
          sessionId: session.id,
          target: const CodexReviewUncommittedChangesTarget(),
        );
        expect(review.reviewThreadId, session.threadId);

        final updated = service.sessions.singleWhere(
          (item) => item.id == session.id,
        );
        expect(updated.lastTurnId, review.turn.id);
      },
    );
  });
}
