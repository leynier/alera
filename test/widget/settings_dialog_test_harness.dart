part of 'settings_dialog_test.dart';

class _FakeUpdateService implements AleraUpdateService {
  @override
  final AleraUpdateConfig config = AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://github.com/leynier/alera'),
    channel: AleraUpdateChannel.stable,
    autoInstallEnabled: false,
    signedRelease: false,
  );

  @override
  final PackageManagerInstall packageInstall = PackageManagerInstall.unmanaged;

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

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository([AleraSettings? initialSettings])
    : _settings = initialSettings ?? AleraSettings.defaults;

  AleraSettings _settings;

  @override
  Future<AleraSettings> load() async => _settings;

  @override
  Future<void> save(AleraSettings settings) async {
    _settings = settings;
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this._projects);

  final List<Project> _projects;

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

class _FakeSystemFontService implements SystemFontService {
  const _FakeSystemFontService(this.fonts);

  final List<String> fonts;

  @override
  Future<List<String>> listFontFamilies() async => fonts;
}

class _FakeAiAssistModelDiscoveryService
    implements AiAssistModelDiscoveryService {
  const _FakeAiAssistModelDiscoveryService();

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

class _DelayedSystemFontService implements SystemFontService {
  _DelayedSystemFontService(this.futureFonts);

  final Future<List<String>> futureFonts;

  @override
  Future<List<String>> listFontFamilies() => futureFonts;
}

class _FakeGitHubStarController extends GitHubStarController {
  _FakeGitHubStarController(this.initialState, {this.nextStarState});

  final GitHubStarState initialState;
  final GitHubStarState? nextStarState;

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

class _FakeFileSelectorPlatform extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelectorPlatform(this.responses);

  final List<Object?> responses;
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

class _DirectoryRequest {
  const _DirectoryRequest({
    required this.initialDirectory,
    required this.confirmButtonText,
    required this.canCreateDirectories,
  });

  final String? initialDirectory;
  final String? confirmButtonText;
  final bool? canCreateDirectories;
}

class _FakeRuntimeHostClient implements RuntimeHostClient {
  _FakeRuntimeHostClient(
    this.targets, {
    this.bootstrapPlanGate,
    this.bootstrapStartGate,
    this.bootstrapCancelGate,
  });

  final List<SshTarget> targets;
  final Completer<void>? bootstrapPlanGate;
  final Completer<void>? bootstrapStartGate;
  final Completer<void>? bootstrapCancelGate;
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
          bootstrapStatus: SshBootstrapStatus.cancelled,
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

class _RuntimeRequest {
  const _RuntimeRequest(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}

/// These dialog tests assert UI behavior, not event coalescing, so they drive
/// the runtime watchers without a debounce window to wait out.
RuntimeChangeCoalescer _immediateCoalescer() {
  return RuntimeChangeCoalescer(
    debounce: Duration.zero,
    maxDelay: Duration.zero,
  );
}
