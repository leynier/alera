import 'package:alera/src/features/remote_hosts/domain/remote_host_check_result.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_address.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_in_use_exception.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only an offline host draws a dot and a disconnected one is ready', () {
    const disconnected = RemoteHostDisconnected();
    expect(disconnected.showsDot, isFalse);
    expect(disconnected.isReady, isTrue);
    expect(disconnected.severity, 0);
    expect(const RemoteHostOffline().showsDot, isTrue);
  });

  test('only a running install counts as busy', () {
    expect(SshBootstrapStatus.installing.isBusy, isTrue);
    expect(SshBootstrapStatus.installed.isBusy, isFalse);
  });

  test('a bootstrap plan reads every field and skips non-string steps', () {
    final plan = SshTargetBootstrapPlan.fromJson(<String, Object?>{
      'targetId': 'mac',
      'platform': 'macos',
      'arch': 'arm64',
      'installDir': '~/.alera/sidecar',
      'channel': 'stable',
      'artifactSource': 'release',
      'trust': 'signed',
      'version': '1.5.0',
      'steps': <Object?>['upload', 3, 'install'],
    });
    expect(plan.targetId, 'mac');
    expect(plan.platform, 'macos');
    expect(plan.arch, 'arm64');
    expect(plan.installDir, '~/.alera/sidecar');
    expect(plan.channel, 'stable');
    expect(plan.artifactSource, 'release');
    expect(plan.trust, 'signed');
    expect(plan.version, '1.5.0');
    expect(plan.steps, <String>['upload', 'install']);
  });

  test('host labels name the alias, This Device, or the raw id', () {
    final targets = <SshTarget>[_target(lastStatus: null)];
    expect(workspaceHostLabel(targets, 'mac'), 'Build Mac');
    expect(workspaceHostLabel(targets, 'local'), 'This Device');
    expect(workspaceHostLabel(targets, 'gone'), 'gone');
  });

  test('a check result reports reachability, time and status', () {
    final checkedAt = DateTime.utc(2026, 10, 12);
    final ready = RemoteHostCheckResult(
      target: _target(
        lastStatus: 'runtimeReady',
        lastCheckedAt: checkedAt,
        hostStatus: const RemoteHostConnected(),
      ),
    );
    expect(ready.reachable, isTrue);
    expect(ready.runtimeInstalled, isTrue);
    expect(ready.checkedAt, checkedAt);
    expect(ready.status, isA<RemoteHostConnected>());

    final reachable = RemoteHostCheckResult(
      target: _target(lastStatus: 'reachable'),
    );
    expect(reachable.reachable, isTrue);
    expect(reachable.runtimeInstalled, isFalse);

    final unreachable = RemoteHostCheckResult(
      target: _target(lastStatus: 'unreachable'),
    );
    expect(unreachable.reachable, isFalse);
    expect(unreachable.status, isNull);
  });

  test('platform hints normalize every spelling', () {
    expect(normalizedRemoteHostPlatform('Linux'), 'linux');
    expect(normalizedRemoteHostPlatform('Windows_NT'), 'windows');
    expect(normalizedRemoteHostPlatform('Darwin'), 'macos');
    expect(normalizedRemoteHostPlatform('plan9'), '');
  });

  test('advanced values compare trimmed text and store the identity file', () {
    const values = RemoteHostAdvancedValues(
      installDir: ' ~/.alera ',
      identityFile: '~/.ssh/id_ed25519',
    );
    expect(
      values.sameAs(
        const RemoteHostAdvancedValues(
          installDir: '~/.alera',
          identityFile: '~/.ssh/id_ed25519',
        ),
      ),
      isTrue,
    );
    expect(
      values.sameAs(const RemoteHostAdvancedValues(installDir: ' ~/.alera ')),
      isFalse,
    );

    final saved = values.applyTo(
      _target(lastStatus: null),
      now: DateTime.utc(2026, 10, 12),
    );
    expect(saved.identityFile, '~/.ssh/id_ed25519');
    final cleared = const RemoteHostAdvancedValues(identityFile: '')
        .applyTo(saved, now: DateTime.utc(2026, 10, 12));
    expect(cleared.identityFile, isNull);
  });

  test('an in-use host with no counts still asks to remove its work', () {
    expect(
      const SshTargetInUseException(
        hostId: 'mac',
        alias: 'Build Mac',
      ).toString(),
      'Build Mac is still in use. Remove its projects and workspaces first.',
    );
  });

  test('a cancelled or settled install leaves steps idle', () {
    const cancelled = RemoteHostInstallProgress(
      targetId: 'mac',
      status: SshBootstrapStatus.cancelled,
    );
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.steps.first.state, RemoteHostInstallStepState.skipped);

    for (final status in <SshBootstrapStatus>[
      SshBootstrapStatus.notInstalled,
      SshBootstrapStatus.planned,
    ]) {
      final steps = RemoteHostInstallProgress(
        targetId: 'mac',
        status: status,
      ).steps;
      expect(
        steps.map((step) => step.state).toSet(),
        <RemoteHostInstallStepState>{RemoteHostInstallStepState.pending},
      );
    }
  });

  test('an SSH address prints as its formatted text', () {
    const address = SshAddress(username: 'me', host: 'mac.local', port: 2222);
    expect(address.toString(), 'me@mac.local:2222');
  });
}

SshTarget _target({
  required String? lastStatus,
  DateTime? lastCheckedAt,
  RemoteHostStatus? hostStatus,
}) {
  final now = DateTime.utc(2026, 10, 1);
  return SshTarget(
    id: 'mac',
    alias: 'Build Mac',
    host: 'mac.local',
    port: 22,
    username: 'me',
    authKind: SshAuthKind.key,
    createdAt: now,
    updatedAt: now,
    lastStatus: lastStatus,
    lastCheckedAt: lastCheckedAt,
    hostStatus: hostStatus,
  );
}
