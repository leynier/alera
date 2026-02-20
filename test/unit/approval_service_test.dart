import 'package:alera/src/features/approvals/application/approval_service.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fakes.dart';

void main() {
  group('ApprovalService', () {
    test('blocks write commands in plan mode even with full access', () async {
      final service = ApprovalService(preferencesStore: InMemoryStringStore());

      final decision = await service.evaluate(
        sessionId: 's1',
        projectPath: '/repo',
        request: const CommandApprovalRequest(
          command: 'echo hello > file.txt',
          cwd: '/repo',
          mode: ExecutionMode.plan,
          fullAccess: true,
          actions: <CommandAction>{CommandAction.filesystemWrite},
        ),
        policy: ApprovalPolicy.ask,
      );

      expect(decision.approved, isFalse);
      expect(decision.reason, contains('plan mode'));
    });

    test('approves full access in normal mode', () async {
      final service = ApprovalService(preferencesStore: InMemoryStringStore());

      final decision = await service.evaluate(
        sessionId: 's1',
        projectPath: '/repo',
        request: const CommandApprovalRequest(
          command: 'git status',
          cwd: '/repo',
          mode: ExecutionMode.normal,
          fullAccess: true,
        ),
        policy: ApprovalPolicy.ask,
      );

      expect(decision.approved, isTrue);
      expect(decision.reason, contains('full access'));
    });

    test('allowlist precedence is session > project > global', () async {
      final store = InMemoryStringStore();
      final service = ApprovalService(preferencesStore: store);

      await service.allowCommand(
        scope: AllowScope.global,
        commandPattern: 'git',
        sessionId: 's1',
        projectPath: '/repo',
      );
      await service.allowCommand(
        scope: AllowScope.project,
        commandPattern: 'git',
        sessionId: 's1',
        projectPath: '/repo',
      );
      await service.allowCommand(
        scope: AllowScope.session,
        commandPattern: 'git',
        sessionId: 's1',
        projectPath: '/repo',
      );

      final decision = await service.evaluate(
        sessionId: 's1',
        projectPath: '/repo',
        request: const CommandApprovalRequest(
          command: 'git status',
          cwd: '/repo',
          mode: ExecutionMode.normal,
          fullAccess: false,
        ),
        policy: ApprovalPolicy.ask,
      );

      expect(decision.approved, isTrue);
      expect(decision.allowScope, AllowScope.session);
    });

    test('denyAll policy rejects commands with no allowlist match', () async {
      final service = ApprovalService(preferencesStore: InMemoryStringStore());

      final decision = await service.evaluate(
        sessionId: 's1',
        projectPath: '/repo',
        request: const CommandApprovalRequest(
          command: 'ls -la',
          cwd: '/repo',
          mode: ExecutionMode.normal,
          fullAccess: false,
        ),
        policy: ApprovalPolicy.denyAll,
      );

      expect(decision.approved, isFalse);
      expect(decision.reason, contains('denied'));
    });
  });
}
