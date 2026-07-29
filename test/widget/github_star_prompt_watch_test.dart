import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/features/settings/presentation/github_star_prompt_watch.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Far enough in the past that DateTime.now() in the prompt host always qualifies.
  final oldProject = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/tmp/alera',
    createdAt: DateTime.utc(2020, 1, 1),
    updatedAt: DateTime.utc(2020, 1, 1),
  );
  final youngProject = Project(
    id: 'project-2',
    name: 'Fresh',
    repoPath: '/tmp/fresh',
    createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
  );

  group('GitHubStarPromptWatch', () {
    testWidgets('shows once when usage is old enough and not muted', (
      tester,
    ) async {
      await _pump(
        tester,
        projects: <Project>[oldProject],
        starState: GitHubStarState.notStarred,
      );

      expect(find.text('Support Alera'), findsOneWidget);
      expect(
        find.text(
          'If this is useful, consider starring the repo. '
          'It helps more developers discover it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Star On GitHub'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);
    });

    testWidgets('does not show when muted, too early, or already starred', (
      tester,
    ) async {
      await _pump(
        tester,
        projects: <Project>[oldProject],
        starState: GitHubStarState.notStarred,
        settings: AleraSettings.defaults.copyWith(
          general: const GeneralSettings(starClicked: true),
        ),
      );
      expect(find.text('Support Alera'), findsNothing);

      await _pump(
        tester,
        projects: <Project>[youngProject],
        starState: GitHubStarState.notStarred,
      );
      expect(find.text('Support Alera'), findsNothing);

      await _pump(
        tester,
        projects: <Project>[oldProject],
        starState: GitHubStarState.starred,
      );
      expect(find.text('Support Alera'), findsNothing);
    });

    testWidgets('Not Now mutes permanently', (tester) async {
      final repository = _FakeSettingsRepository();
      final container = await _pump(
        tester,
        projects: <Project>[oldProject],
        starState: GitHubStarState.notStarred,
        repository: repository,
      );

      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      expect(find.text('Support Alera'), findsNothing);
      expect(
        container.read(settingsControllerProvider).general.starClicked,
        isTrue,
      );
      expect((await repository.load()).general.starClicked, isTrue);
    });

    testWidgets('confirm stars via gh when available and mutes', (
      tester,
    ) async {
      final repository = _FakeSettingsRepository();
      final launcher = _FakeExternalUriLauncher();
      final starController = _FakeGitHubStarController(
        GitHubStarState.notStarred,
        nextStarState: GitHubStarState.starred,
      );
      final container = await _pump(
        tester,
        projects: <Project>[oldProject],
        starController: starController,
        repository: repository,
        launcher: launcher,
      );

      await tester.tap(find.text('Star On GitHub'));
      await tester.pumpAndSettle();

      expect(starController.starCalls, 1);
      expect(launcher.opened, isEmpty);
      expect(
        container.read(settingsControllerProvider).general.starClicked,
        isTrue,
      );
      expect(find.text('Support Alera'), findsNothing);
    });

    testWidgets('confirm opens the repo URL when gh cannot star', (
      tester,
    ) async {
      final repository = _FakeSettingsRepository();
      final launcher = _FakeExternalUriLauncher();
      final starController = _FakeGitHubStarController(GitHubStarState.hidden);
      final container = await _pump(
        tester,
        projects: <Project>[oldProject],
        starController: starController,
        repository: repository,
        launcher: launcher,
      );

      await tester.tap(find.text('Star On GitHub'));
      await tester.pumpAndSettle();

      expect(starController.starCalls, 0);
      expect(launcher.opened, <Uri>[Uri.parse(aleraGitHubUrl)]);
      expect(
        container.read(settingsControllerProvider).general.starClicked,
        isTrue,
      );
    });

    testWidgets('confirm falls back to the URL after a failed star', (
      tester,
    ) async {
      final launcher = _FakeExternalUriLauncher();
      final starController = _FakeGitHubStarController(
        GitHubStarState.notStarred,
        nextStarState: GitHubStarState.error,
      );
      await _pump(
        tester,
        projects: <Project>[oldProject],
        starController: starController,
        launcher: launcher,
      );

      await tester.tap(find.text('Star On GitHub'));
      await tester.pumpAndSettle();

      expect(starController.starCalls, 1);
      expect(launcher.opened, <Uri>[Uri.parse(aleraGitHubUrl)]);
    });
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Project> projects,
  GitHubStarState starState = GitHubStarState.notStarred,
  _FakeGitHubStarController? starController,
  AleraSettings settings = AleraSettings.defaults,
  _FakeSettingsRepository? repository,
  _FakeExternalUriLauncher? launcher,
}) async {
  final settingsRepository = repository ?? _FakeSettingsRepository(settings);
  final star = starController ?? _FakeGitHubStarController(starState);
  final uriLauncher = launcher ?? _FakeExternalUriLauncher();
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      projectListProvider.overrideWith((ref) => Stream.value(projects)),
      gitHubStarControllerProvider.overrideWith(() => star),
      externalUriLauncherProvider.overrideWithValue(uriLauncher),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const GitHubStarPromptWatch(
          child: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    ),
  );
  // Settings load + post-frame dialog presentation.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
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

class _FakeGitHubStarController extends GitHubStarController {
  _FakeGitHubStarController(this.initialState, {this.nextStarState});

  final GitHubStarState initialState;
  final GitHubStarState? nextStarState;
  int starCalls = 0;

  @override
  GitHubStarState build() => initialState;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> star() async {
    starCalls += 1;
    if (state != GitHubStarState.notStarred && state != GitHubStarState.error) {
      return;
    }
    state = GitHubStarState.starring;
    state = nextStarState ?? GitHubStarState.starred;
  }
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
  }
}
