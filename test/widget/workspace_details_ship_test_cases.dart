part of 'workspace_details_overlay_test.dart';

class _ShipSettings extends SettingsController {
  _ShipSettings(this.seed);
  final AleraSettings seed;
  @override
  AleraSettings build() => seed;
  @override
  Future<void> setPullRequestAgentWatchScope(
    PullRequestAgentWatchScope value,
  ) async => state = state.copyWith(
    general: state.general.copyWith(pullRequestAgentWatchScope: value),
  );
  @override
  Future<void> setPullRequestShipFollowUp(
    PullRequestShipFollowUp value,
  ) async => state = state.copyWith(
    general: state.general.copyWith(pullRequestShipFollowUp: value),
  );
}

class _ShipReviews extends _Reviews {
  _ShipReviews(super.snapshot);
  final shipped = <({String base, bool draft, PullRequestShipScope scope})>[];
  @override
  Future<CreateReviewResult> ship({
    required String baseBranch,
    required bool draft,
    required AiAssistSettings settings,
    required PullRequestShipScope scope,
  }) async {
    shipped.add((base: baseBranch, draft: draft, scope: scope));
    return const CreateReviewFailure(code: .blocked, message: 'Recorded');
  }
}

const _shippable = WorkspacePullRequestState(
  identity: GitRemoteIdentity(
    provider: .github,
    host: 'github.com',
    owner: 'alera',
    repo: 'alera',
  ),
  authStatus: .authenticated,
  currentBranch: 'feature/details',
  suggestedBaseBranch: 'develop',
);

Future<({_ShipSettings settings, _ShipReviews reviews})> _pumpShip(
  WidgetTester tester, {
  AleraSettings settings = AleraSettings.defaults,
  WorkspacePullRequestState reviewState = _shippable,
}) async {
  final settingsController = _ShipSettings(settings);
  final reviews = _ShipReviews(reviewState);
  await pumpOverlay(
    tester,
    const Size(1000, 900),
    overrides: [
      settingsControllerProvider.overrideWith(() => settingsController),
    ],
    reviews: () => reviews,
  );
  await tester.tap(find.byTooltip('Commit & Push Options'));
  await tester.pumpAndSettle();
  return (settings: settingsController, reviews: reviews);
}

bool _entryEnabled(WidgetTester tester, String label) => tester
    .widget<AleraDropdownEntry<String>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AleraDropdownEntry<String>),
      ),
    )
    .enabled;

void _registerWorkspaceDetailsShipTests() {
  testWidgets('the git menu offers Ship follow-ups and watch toggles', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pumped = await _pumpShip(tester);
    double top(String label) => tester.getRect(find.text(label).last).top;
    expect(top('Pull'), lessThan(top('Ship Changes')));
    expect(top('Ship Changes'), lessThan(top('Ship, Watch and Fix')));
    expect(top('Ship, Watch, Fix and Merge'), lessThan(top('Failed Checks')));
    expect(top('Merge Conflicts'), lessThan(top('Refresh')));
    expect(_entryEnabled(tester, 'Ship, Watch and Fix'), isTrue);

    for (final label in [
      'Failed Checks',
      'Review Comments',
      'Merge Conflicts',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(
      pumped.settings.state.general.pullRequestAgentWatchScope.isEmpty,
      isTrue,
    );
    // The menu stays open, and watching nothing turns the watch rows off.
    expect(_entryEnabled(tester, 'Ship, Watch and Fix'), isFalse);
    expect(_entryEnabled(tester, 'Ship Changes'), isTrue);
  });

  testWidgets('Ship is off without a pull request to create', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShip(tester, reviewState: const WorkspacePullRequestState());
    expect(_entryEnabled(tester, 'Ship Changes'), isFalse);
  });

  testWidgets('picking a Ship follow-up ships and remembers it', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pumped = await _pumpShip(
      tester,
      settings: AleraSettings.defaults.copyWith(
        general: AleraSettings.defaults.general.copyWith(
          pullRequestShipFollowUp: .watchAndFix,
        ),
      ),
    );
    await tester.tap(find.text('Ship Changes'));
    await tester.pumpAndSettle();
    // The working tree has changes, so Ship asks what to include.
    await tester.tap(find.text('Ship All Changes'));
    await tester.pumpAndSettle();
    expect(pumped.reviews.shipped, [
      (base: 'develop', draft: false, scope: PullRequestShipScope.all),
    ]);
    expect(
      pumped.settings.state.general.pullRequestShipFollowUp,
      PullRequestShipFollowUp.none,
    );
  });
}
