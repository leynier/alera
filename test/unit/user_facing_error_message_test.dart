import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native_files;
import 'package:alera/src/shared/infra/git/git_error_message.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('userFacingErrorMessage', () {
    test('drops the Bad state prefix from a StateError', () {
      final message = userFacingErrorMessage(
        StateError('Workspace has running agents.'),
      );

      expect(message, 'Workspace has running agents.');
      expect(message, isNot(contains('Bad state')));
    });

    test('strips nested Dart type prefixes', () {
      expect(
        userFacingErrorMessage('Bad state: FormatException: Invalid JSON.'),
        'Invalid JSON.',
      );
      expect(
        userFacingErrorMessage(
          StateError('FormatException: Unexpected end of input'),
        ),
        'Unexpected end of input',
      );
    });

    test('drops the Exception prefix', () {
      expect(
        userFacingErrorMessage(Exception('Port 4000 is already in use.')),
        'Port 4000 is already in use.',
      );
    });

    test('maps each git failure to its sentence', () {
      final cases = <GitException, String>{
        const NotARepositoryException('/tmp/repo'):
            'This workspace is not a Git repository.',
        const DetachedHeadException('HEAD'): 'Cannot push from detached HEAD.',
        const BranchAlreadyExistsException('feature/login'):
            'A branch named "feature/login" already exists.',
        const BranchNotFoundException('feature/login'):
            'Branch "feature/login" was not found.',
        const InvalidBranchNameException('bad..name'):
            'Enter a valid branch name.',
        const RemoteNotFoundException('origin'): 'Remote origin was not found.',
        const NothingToCommitException(''): 'Nothing to commit.',
        const GitConflictException(''): 'Resolve conflicts before continuing.',
        const GitConflictException('Merge conflict in lib/main.dart'):
            'Merge conflict in lib/main.dart',
        const GitCliException(''): 'Git operation failed.',
        const GitCliException('rejected: non-fast-forward'):
            'Rejected: non-fast-forward',
        const NoUpstreamException('The branch has no upstream.'):
            'The branch has no upstream.',
        const MissingIdentityException('Set user.name and user.email.'):
            'Set user.name and user.email.',
      };
      for (final MapEntry(key: error, value: expected) in cases.entries) {
        expect(
          userFacingErrorMessage(error),
          expected,
          reason: error.runtimeType.toString(),
        );
      }
    });

    test('never shows the git exception class name', () {
      final message = userFacingErrorMessage(
        const AccessDeniedException('Permission denied: .git/index'),
      );

      expect(message, 'Permission denied: .git/index');
      expect(message, isNot(contains('AccessDeniedException')));
    });

    test('cleans a Bad state context inside a GitInternalException', () {
      final message = userFacingErrorMessage(
        const GitInternalException('Bad state: index file is locked'),
      );

      expect(message, 'Index file is locked');
      expect(message, isNot(contains('Bad state')));
      expect(message, isNot(contains('GitInternalException')));
    });

    test('gitErrorMessage keeps the runtime wording for typed failures', () {
      expect(
        gitErrorMessage(const GitInternalException('  ')),
        'Git operation failed.',
      );
      expect(
        gitErrorMessage(const BranchNotFoundException(' main ')),
        'Branch "main" was not found.',
      );
    });

    test('uses the forge message without the class name', () {
      final message = userFacingErrorMessage(
        const ForgeRequestFailed('HTTP 502 from the GitHub API'),
      );

      expect(message, 'HTTP 502 from the GitHub API');
      expect(message, isNot(contains('ForgeRequestFailed')));
    });

    test('uses the AI Assist message', () {
      expect(
        userFacingErrorMessage(
          const AiAssistException('Codex exited with code 1.'),
        ),
        'Codex exited with code 1.',
      );
    });

    test('uses the runtime conflict message, capitalized', () {
      expect(
        userFacingErrorMessage(
          const TerminalHostConflictException(
            code: 'workspaceArchived',
            message: 'workspace is archived',
          ),
        ),
        'Workspace is archived',
      );
    });

    test('explains a runtime request timeout in seconds', () {
      expect(
        userFacingErrorMessage(
          const TerminalHostRequestTimeoutException(
            'status.get',
            Duration(seconds: 10),
          ),
        ),
        'The Alera runtime did not answer within 10 seconds. Try again, or '
        'restart the runtime from the status bar if this keeps happening.',
      );
      expect(
        userFacingErrorMessage(
          const TerminalHostRequestTimeoutException(
            'status.get',
            Duration(milliseconds: 400),
          ),
        ),
        startsWith('The Alera runtime did not answer within 1 second.'),
      );
    });

    test('explains a closed runtime connection with and without a reason', () {
      expect(
        userFacingErrorMessage(const TerminalHostConnectionClosedException()),
        'Lost the connection to the Alera runtime.',
      );
      expect(
        userFacingErrorMessage(
          const TerminalHostConnectionClosedException(
            'Bad state: socket reset by peer',
          ),
        ),
        'Lost the connection to the Alera runtime: Socket reset by peer',
      );
    });

    test('combines a workspace file error kind with its context', () {
      expect(
        userFacingErrorMessage(
          const native_files.WorkspaceFileError(
            kind: .io,
            context: 'Permission denied (os error 13)',
          ),
        ),
        'The file operation failed: Permission denied (os error 13)',
      );
      expect(
        userFacingErrorMessage(
          const native_files.WorkspaceFileError(kind: .notFound, context: ''),
        ),
        'The item was not found.',
      );
    });

    test('includes the path and OS error of a FileSystemException', () {
      expect(
        userFacingErrorMessage(
          const FileSystemException(
            'Cannot open file',
            '/tmp/alera/settings.json',
            OSError('No such file or directory', 2),
          ),
        ),
        'Cannot open file (/tmp/alera/settings.json): '
        'No such file or directory',
      );
    });

    test('names the executable of a ProcessException', () {
      expect(
        userFacingErrorMessage(
          const ProcessException(
            'gh',
            <String>['pr', 'view'],
            'No such file or directory',
            2,
          ),
        ),
        'Could not run gh: No such file or directory',
      );
    });

    test('describes a TimeoutException without a message', () {
      expect(
        userFacingErrorMessage(
          TimeoutException(null, const Duration(seconds: 3)),
        ),
        'The operation did not finish within 3 seconds.',
      );
    });

    test('replaces an Instance of text with the unknown message', () {
      expect(userFacingErrorMessage(_Opaque()), unknownErrorMessage);
    });

    test('never returns an empty string', () {
      expect(userFacingErrorMessage(null), unknownErrorMessage);
      expect(userFacingErrorMessage(''), unknownErrorMessage);
      expect(userFacingErrorMessage('   '), unknownErrorMessage);
      expect(userFacingErrorMessage(StateError('')), unknownErrorMessage);
      expect(
        userFacingErrorMessage('', fallback: '  Try again later.  '),
        'Try again later.',
      );
      expect(userFacingErrorMessage('', fallback: '  '), unknownErrorMessage);
    });

    test('capitalizes a lowercase first word but keeps command names', () {
      expect(
        userFacingErrorMessage('cannot push detached HEAD'),
        'Cannot push detached HEAD',
      );
      expect(
        userFacingErrorMessage('git fetch exited with code 128'),
        'git fetch exited with code 128',
      );
      expect(
        userFacingErrorMessage('npm install exited with code 1'),
        'npm install exited with code 1',
      );
      expect(
        userFacingErrorMessage('./setup.sh exited with code 2'),
        './setup.sh exited with code 2',
      );
      expect(
        userFacingErrorMessage('pnpm-lock.yaml is out of date'),
        'pnpm-lock.yaml is out of date',
      );
    });
  });

  group('stripErrorTypePrefixes', () {
    test('removes every nested prefix and nothing else', () {
      expect(
        stripErrorTypePrefixes(
          'Exception: Bad state: FormatException: Bad input: line 3',
        ),
        'Bad input: line 3',
      );
      expect(
        stripErrorTypePrefixes('Invalid argument(s): Value must be positive'),
        'Value must be positive',
      );
      expect(
        stripErrorTypePrefixes('Unsupported operation: Read only'),
        'Read only',
      );
      expect(stripErrorTypePrefixes('  Plain text  '), 'Plain text');
    });
  });

  group('actionFailureMessage', () {
    test('leads with the action and ends with the cause', () {
      expect(
        actionFailureMessage(
          ' archive workspace ',
          StateError('Workspace has running agents.'),
        ),
        'Could not archive workspace: Workspace has running agents.',
      );
    });

    test('falls back to the unknown message when the cause is empty', () {
      const expected =
          'Could not archive workspace. '
          'An unexpected error occurred. See the logs for details.';
      expect(actionFailureMessage('archive workspace', null), expected);
      expect(actionFailureMessage('archive workspace', ''), expected);
      expect(actionFailureMessage('archive workspace', _Opaque()), expected);
    });
  });
}

class _Opaque {}
