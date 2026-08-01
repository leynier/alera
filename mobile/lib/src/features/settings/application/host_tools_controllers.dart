import 'dart:async';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_tools_controllers.g.dart';

@riverpod
class SkillRunnerSelection extends _$SkillRunnerSelection {
  @override
  String build(String hostId, String skill) => 'auto';

  void select(String value) {
    state = value;
  }
}

@riverpod
class CliRegistrationController extends _$CliRegistrationController {
  @override
  Future<CliRegistrationStatus> build(String hostId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsHostTools) {
      throw UnsupportedError('Update the runtime to manage host tools.');
    }
    return client.cliRegistrationStatus();
  }

  Future<void> install() async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    state = const AsyncLoading<CliRegistrationStatus>();
    state = await AsyncValue.guard(client.installCliRegistration);
  }
}

class SkillInstallState {
  const SkillInstallState({this.phase = 'idle', this.message, this.result});

  final String phase;
  final String? message;
  final SkillInstallResult? result;
}

@riverpod
class SkillInstallController extends _$SkillInstallController {
  StreamSubscription<Object?>? _subscription;
  String? _operationId;

  @override
  SkillInstallState build(String hostId, String skill) {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return const SkillInstallState();
  }

  Future<void> install(String runner) async {
    if (state.phase == 'installing') {
      return;
    }
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsHostTools) {
      state = const SkillInstallState(
        phase: 'failed',
        message: 'Update the runtime to install skills.',
      );
      return;
    }
    _operationId = '${DateTime.now().microsecondsSinceEpoch}-$skill';
    await _subscription?.cancel();
    _subscription = client.events.listen((event) {
      if (event.name != 'agentSkillInstallProgress' ||
          event.payload['operationId'] != _operationId) {
        return;
      }
      state = SkillInstallState(
        phase: event.payload['phase'] as String? ?? 'installing',
        message: event.payload['message'] as String?,
      );
    });
    state = const SkillInstallState(
      phase: 'installing',
      message: 'Installing skill',
    );
    try {
      final result = await client.installSkill(
        skill: skill,
        runner: runner,
        operationId: _operationId,
      );
      state = SkillInstallState(
        phase: result.succeeded ? 'completed' : 'failed',
        message: result.summary,
        result: result,
      );
    } on Object catch (error) {
      state = SkillInstallState(phase: 'failed', message: error.toString());
    }
  }
}
