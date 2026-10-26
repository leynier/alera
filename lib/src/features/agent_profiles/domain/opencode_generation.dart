/// Which OpenCode generation `opencode` runs.
///
/// OpenCode v1 and OpenCode 2 both install as `opencode`, and a v1 install
/// stays on v1 until the user upgrades. Their command lines differ and both
/// reject flags they do not know: OpenCode 2 needs `--standalone` for a
/// private server and takes the thinking level as `model#variant`, while v1
/// takes `--model`/`--agent` on the TUI and `--variant` on `run`. Mirrors
/// `rust/alera-cli/src/terminal_host/orchestration/opencode_generation.rs`.
enum OpenCodeGeneration {
  v1,
  v2;

  /// The generation upstream ships today, used until a probe says otherwise.
  static const OpenCodeGeneration fallback = OpenCodeGeneration.v2;

  /// Reads `opencode --version`: `1.19.4` on v1, `opencode v2.1.4` on v2.
  static OpenCodeGeneration? fromVersionOutput(String output) {
    for (final token in output.split(RegExp(r'\s+'))) {
      final version = token.startsWith('v') ? token.substring(1) : token;
      final major = int.tryParse(version.split('.').first);
      if (major != null) {
        return major <= 1 ? v1 : v2;
      }
    }
    return null;
  }
}

/// `opencode run` for AI Assist in the shape [generation] accepts.
List<String> openCodeRunArguments({
  required String model,
  required String? thinkingLevel,
  required OpenCodeGeneration generation,
}) {
  final v2Thinking =
      generation == OpenCodeGeneration.v2 && thinkingLevel != null;
  return <String>[
    'run',
    '--model',
    v2Thinking ? '$model#$thinkingLevel' : model,
    '--agent',
    'build',
    '--format',
    'default',
    if (generation == OpenCodeGeneration.v1 &&
        thinkingLevel != null) ...<String>['--variant', thinkingLevel],
  ];
}
