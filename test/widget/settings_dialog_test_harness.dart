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
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    return const AleraUpdateCheckResult(message: 'Alera is up to date.');
  }

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

class _FakeSystemFontService implements SystemFontService {
  const _FakeSystemFontService(this.fonts);

  final List<String> fonts;

  @override
  Future<List<String>> listFontFamilies() async => fonts;
}

class _FakeAiTextModelDiscoveryService implements AiTextModelDiscoveryService {
  const _FakeAiTextModelDiscoveryService();

  static const List<AiTextModel> _models = <AiTextModel>[
    AiTextModel(
      id: 'gpt-5.5',
      label: 'GPT-5.5',
      thinkingLevels: openAiThinkingLevels,
      defaultThinkingLevel: 'low',
    ),
    AiTextModel(
      id: 'gpt-5.4-mini',
      label: 'GPT-5.4 Mini',
      thinkingLevels: openAiThinkingLevels,
      defaultThinkingLevel: 'low',
    ),
  ];

  @override
  Future<AiTextModelDiscoveryResult> discover(
    AiTextGenerationAgent agent,
  ) async {
    return AiTextModelDiscoveryResult(
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
