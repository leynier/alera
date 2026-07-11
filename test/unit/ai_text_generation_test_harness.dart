part of 'ai_text_generation_service_test.dart';

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({
    required this.stdout,
    this.stderr = '',
    this.exitCode = 0,
    this.exitCodeCompleter,
    this.completeExitOnKill = true,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Completer<int>? exitCodeCompleter;
  final bool completeExitOnKill;
  bool started = false;
  int startCount = 0;
  bool stdinClosed = false;
  bool killed = false;
  String? executable;
  List<String> arguments = const <String>[];
  Map<String, String>? environment;
  String? promptFilePath;
  String? promptFileText;
  String? grokHomePath;
  String? grokAuthText;
  String? grokConfigText;
  final StringBuffer _stdin = StringBuffer();

  String get stdinText => _stdin.toString();

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return ProcessRunOutput(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    started = true;
    startCount += 1;
    this.executable = executable;
    this.arguments = List<String>.from(arguments);
    final promptFileIndex = arguments.indexOf('--prompt-file');
    if (promptFileIndex >= 0 && promptFileIndex + 1 < arguments.length) {
      promptFilePath = arguments[promptFileIndex + 1];
      promptFileText = File(promptFilePath!).readAsStringSync();
    }
    if (executable == 'grok') {
      grokHomePath = environment?['GROK_HOME'];
      final home = grokHomePath;
      if (home != null) {
        final auth = File('$home/auth.json');
        if (auth.existsSync()) {
          grokAuthText = auth.readAsStringSync();
        }
        final config = File('$home/config.toml');
        if (config.existsSync()) {
          grokConfigText = config.readAsStringSync();
        }
      }
    }
    this.environment = environment == null
        ? null
        : Map<String, String>.from(environment);
    return StartedProcess(
      stdinWrite: (data) => _stdin.write(utf8.decode(data)),
      stdinClose: () => stdinClosed = true,
      stdout: Stream<List<int>>.value(utf8.encode(stdout)),
      stderr: Stream<List<int>>.value(utf8.encode(stderr)),
      pid: 1,
      exitCode: exitCodeCompleter?.future ?? Future<int>.value(exitCode),
      kill: ([dynamic signal]) {
        killed = true;
        if (completeExitOnKill) {
          if (exitCodeCompleter case final completer?) {
            if (!completer.isCompleted) {
              completer.complete(143);
            }
          }
        }
        return true;
      },
    );
  }
}

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver({
    this.value = const <String, String>{'PATH': '/usr/bin'},
  });

  final Map<String, String> value;

  @override
  Future<Map<String, String>> environment() async {
    return Map<String, String>.from(value);
  }
}

class _DelayedDiffGitBackend extends FakeGitBackend {
  final Completer<void> _diffGate = Completer<void>();
  bool diffStarted = false;

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async {
    diffStarted = true;
    await _diffGate.future;
    return super.diff(path: path, filePath: filePath, area: area);
  }

  void completeDiff() {
    if (!_diffGate.isCompleted) {
      _diffGate.complete();
    }
  }
}

Future<void> untilCalled(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for call');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
