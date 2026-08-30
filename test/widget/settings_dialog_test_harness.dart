part of 'settings_dialog_test.dart';

class _FakeUpdateService implements AleraUpdateService {
  @override
  final AleraUpdateConfig config = AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://github.com/leynier/alera'),
    channel: .stable,
    autoInstallEnabled: false,
    signedRelease: false,
  );

  @override
  final PackageManagerInstall packageInstall = .unmanaged;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    return const AleraUpdateCheckResult(message: 'Alera is up to date.');
  }

  @override
  Future<void> upgradeThroughPackageManager() async {}

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {}

  @override
  Future<void> restartApp() async {}

  @override
  void dispose() {}
}

class _FakeSettingsRepository([AleraSettings? initialSettings])
    implements SettingsRepository {
  this : _settings = initialSettings ?? AleraSettings.defaults;

  AleraSettings _settings;

  @override
  Future<AleraSettings> load() async => _settings;

  @override
  Future<void> save(AleraSettings settings) async {
    _settings = settings;
  }
}

class _FakeProjectRepository(final List<Project> _projects)
    implements ProjectRepository {
  @override
  Future<Project> add(Project project) {
    throw UnimplementedError();
  }

  @override
  Future<List<Project>> listAll() async {
    return _projects;
  }

  @override
  Future<void> remove(String projectId) {
    throw UnimplementedError();
  }

  @override
  Future<Project> update(Project project) {
    throw UnimplementedError();
  }

  @override
  Stream<List<Project>> watchAll() async* {
    yield _projects;
  }
}

class const _FakeSystemFontService(final List<String> fonts)
    implements SystemFontService {
  @override
  Future<List<String>> listFontFamilies() async => fonts;
}

class const _FakeAiAssistModelDiscoveryService()
    implements AiAssistModelDiscoveryService {
  static const List<AiAssistModel> _models = <AiAssistModel>[
    AiAssistModel(
      id: 'gpt-5.5',
      label: 'GPT-5.5',
      thinkingLevels: openAiThinkingLevels,
      defaultThinkingLevel: 'low',
    ),
    AiAssistModel(
      id: 'gpt-5.4-mini',
      label: 'GPT-5.4 Mini',
      thinkingLevels: openAiThinkingLevels,
      defaultThinkingLevel: 'low',
    ),
  ];

  @override
  Future<AiAssistModelDiscoveryResult> discover(AiAssistAgent agent) async {
    return AiAssistModelDiscoveryResult(
      success: true,
      agent: agent,
      models: _models,
      defaultModelId: _models.first.id,
    );
  }
}

class _DelayedSystemFontService(final Future<List<String>> futureFonts)
    implements SystemFontService {
  @override
  Future<List<String>> listFontFamilies() => futureFonts;
}

class _FakeGitHubStarController(
  final GitHubStarState initialState, {
  final GitHubStarState? nextStarState,
}) extends GitHubStarController {
  @override
  GitHubStarState build() => initialState;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> star() async {
    if (state != GitHubStarState.notStarred && state != GitHubStarState.error) {
      return;
    }
    state = GitHubStarState.starring;
    state = nextStarState ?? GitHubStarState.starred;
  }
}

class _FakeFileSelectorPlatform(final List<Object?> responses)
    extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  final List<_DirectoryRequest> requests = <_DirectoryRequest>[];

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    requests.add(
      _DirectoryRequest(
        initialDirectory: options.initialDirectory,
        confirmButtonText: options.confirmButtonText,
        canCreateDirectories: options.canCreateDirectories,
      ),
    );
    if (responses.isEmpty) {
      return null;
    }
    final next = responses.removeAt(0);
    if (next is Object && next is! String) {
      throw next;
    }
    return next as String?;
  }
}

class const _DirectoryRequest({
  required final String? initialDirectory,
  required final String? confirmButtonText,
  required final bool? canCreateDirectories,
});

class _FakeRuntimeHostClient(
  final List<SshTarget> targets, {
  final Completer<void>? bootstrapPlanGate,
  final Completer<void>? bootstrapStartGate,
  final Completer<void>? bootstrapCancelGate,
}) implements RuntimeHostClient {
  final List<_RuntimeRequest> requests = <_RuntimeRequest>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  void emitSshTargetsChanged() {
    _events.add(
      const RuntimeHostEvent('sshTargetsChanged', <String, Object?>{}),
    );
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(_RuntimeRequest(type, Map<String, Object?>.from(payload)));
    switch (type) {
      case 'sshTarget.list':
        return <Map<String, Object?>>[
          for (final target in targets) target.toJson(),
        ];
      case 'sshTarget.upsert':
        final target = SshTarget.fromJson(payload);
        final index = targets.indexWhere((item) => item.id == target.id);
        if (index == -1) {
          targets.add(target);
        } else {
          targets[index] = target;
        }
        _events.add(
          const RuntimeHostEvent('sshTargetsChanged', <String, Object?>{}),
        );
        return target.toJson();
      case 'sshTarget.bootstrap.plan':
        await bootstrapPlanGate?.future;
        return <String, Object?>{
          'targetId': payload['targetId'],
          'platform': payload['platform'] ?? 'linux',
          'arch': payload['arch'] ?? 'x64',
          'installDir':
              payload['installDir'] ?? '/opt/alera/${payload['targetId']}',
          'channel': payload['channel'] ?? 'stable',
          'artifactSource': 'runtime-archive',
          'trust': 'signedArchive',
          'version': payload['version'],
          'steps': <String>['Download Runtime'],
        };
      case 'sshTarget.bootstrap.start':
        await bootstrapStartGate?.future;
        return <String, Object?>{
          'jobId': 'job-1',
          'targetId': payload['targetId'],
          'status': 'installing',
        };
      case 'sshTarget.bootstrap.cancel':
        await bootstrapCancelGate?.future;
        final targetId = payload['id'] as String;
        final index = targets.indexWhere((target) => target.id == targetId);
        if (index == -1) {
          throw StateError('ssh target not found: $targetId');
        }
        final target = targets[index];
        final cancelled = SshTarget(
          id: target.id,
          alias: target.alias,
          host: target.host,
          port: target.port,
          username: target.username,
          platform: target.platform,
          arch: target.arch,
          authKind: target.authKind,
          createdAt: target.createdAt,
          updatedAt: target.updatedAt,
          lastStatus: target.lastStatus,
          installDir: target.installDir,
          runtimeVersion: target.runtimeVersion,
          runtimePlatform: target.runtimePlatform,
          runtimeArch: target.runtimeArch,
          bootstrapStatus: .cancelled,
          lastBootstrapAt: target.lastBootstrapAt,
          lastCheckedAt: target.lastCheckedAt,
          lastError: null,
        );
        targets[index] = cancelled;
        _events.add(
          const RuntimeHostEvent('sshTargetsChanged', <String, Object?>{}),
        );
        return cancelled.toJson();
      default:
        throw UnimplementedError(type);
    }
  }

  Future<void> dispose() => _events.close();
}

class const _RuntimeRequest(
  final String type,
  final Map<String, Object?> payload,
);

/// These dialog tests assert UI behavior, not event coalescing, so they drive
/// the runtime watchers without a debounce window to wait out.
RuntimeChangeCoalescer _immediateCoalescer() {
  return RuntimeChangeCoalescer(debounce: .zero, maxDelay: .zero);
}
