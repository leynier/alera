import 'dart:async';

import 'package:alera/src/features/agent_profiles/domain/opencode_generation.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Asks the installed `opencode` which generation it is.
///
/// One answer is shared until [refresh], because every caller (a command
/// preview, persona discovery, an AI Assist run) asks the same question and
/// the answer only changes when the user upgrades. A failed or silent probe
/// answers [OpenCodeGeneration.fallback].
class OpenCodeGenerationProbe({
  required final ProcessRunner processRunner,
  required final CommandEnvironmentResolver commandEnvironmentResolver,
}) {
  static const Duration _timeout = Duration(seconds: 5);

  Future<OpenCodeGeneration>? _pending;

  Future<OpenCodeGeneration> detect() => _pending ??= _probe();

  /// Forgets the cached answer, so the next [detect] probes again.
  void refresh() => _pending = null;

  Future<OpenCodeGeneration> _probe() async {
    try {
      final output = await processRunner
          .run('opencode', const <String>[
            '--version',
          ], environment: await commandEnvironmentResolver.environment())
          .timeout(_timeout);
      return OpenCodeGeneration.fromVersionOutput(output.stdout) ??
          OpenCodeGeneration.fromVersionOutput(output.stderr) ??
          OpenCodeGeneration.fallback;
    } catch (_) {
      return OpenCodeGeneration.fallback;
    }
  }
}
