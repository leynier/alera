import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_review_row.dart';
import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _longBranch = 'feature/workspace-details-with-a-very-long-branch-name';
const _longTitle =
    '#4821: Keep the workspace details card calm when a pull request title '
    'runs much longer than the card is wide';

class _Calls {
  final pressed = <String>[];
  VoidCallback call(String id) =>
      () => pressed.add(id);
}

Widget _card(
  _Calls calls, {
  double width = AleraTokens.workspaceDetailsWidth,
  WorkspaceDetailsDensity density = .full,
  bool long = false,
  bool running = false,
  String? error,
  bool critical = false,
  bool pending = false,
  GlobalKey? capture,
}) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: capture,
        child: SizedBox(
          width: width,
          child: AleraWorkspaceDetailsCard(
            density: density,
            onOptions: (_) => calls('options')(),
            afterBranch: AleraWorkspaceReviewRow(
              label: long ? _longTitle : '#123: Add Workspace Details',
              stateLabel: 'Open',
              stateIcon: AleraIcons.gitPullRequest,
              stateColor: AleraTokens.success,
              tooltip: 'feature/workspace-details → main',
              onOpen: calls('pr'),
              onMenu: (_) => calls('pr-menu')(),
              checksLabel: critical ? '5 Checks' : '2 Checks',
              checksIcon: critical ? AleraIcons.cancel : AleraIcons.success,
              checksColor: critical ? AleraTokens.error : AleraTokens.success,
              onChecks: calls('checks'),
              actionLabel: pending
                  ? 'Merging…'
                  : critical
                  ? 'Fix'
                  : 'Merge',
              actionCritical: critical,
              actionPending: pending,
              onAction: pending ? null : calls('action'),
              compact: density != .full,
            ),
            workspaceRows: [
              AleraWorkspaceDetailRow(
                label: long ? 'build-server-with-a-long-hostname.lan' : 'host',
                leading: const AleraHostOsIcon(
                  os: HostOs.linux,
                  size: AleraTokens.iconMd,
                ),
                onPressed: calls('host'),
                onMenu: (_) => calls('host-menu')(),
              ),
              AleraWorkspaceDetailRow(
                label: 'Open In File Manager',
                leading: const Icon(AleraIcons.folder),
                onPressed: calls('open'),
                onMenu: (_) => calls('open-menu')(),
              ),
            ],
            gitRows: [
              AleraWorkspaceDetailRow(
                label: long ? _longBranch : 'feature/workspace-details',
                subtitle: 'Compare against origin/main',
                leading: const Icon(AleraIcons.gitBranch),
                hasMenu: true,
                onPressed: running ? null : calls('branch'),
                onMenu: running ? null : (_) => calls('branch-menu')(),
              ),
              AleraWorkspaceDetailRow(
                label: running
                    ? 'Pushing'
                    : error != null
                    ? 'Push'
                    : 'Commit, Push & Create PR',
                subtitle:
                    error ?? (running ? '12s · Writing objects: 64%' : null),
                subtitleColor: error == null ? null : AleraTokens.error,
                leading: running
                    ? const AleraWorkspaceDetailSpinner()
                    : error != null
                    ? const Icon(AleraIcons.error, color: AleraTokens.error)
                    : const Icon(AleraIcons.gitPush),
                hasMenu: true,
                onPressed: running ? null : calls('git'),
                onMenu: running ? null : (_) => calls('git-menu')(),
              ),
              AleraWorkspaceDetailRow(
                label: 'Changes',
                leading: const Icon(AleraIcons.diff),
                trailing: Text(
                  '+42',
                  style: AleraTokens.monoCompactStyle.copyWith(
                    color: AleraTokens.success,
                  ),
                ),
                onPressed: calls('changes'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> _save(WidgetTester tester, GlobalKey capture, String name) async {
  final directory = Platform.environment['ALERA_VISUAL_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/workspace-details-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('labels share one text column across rows and the PR meta line', (
    tester,
  ) async {
    await tester.pumpWidget(_card(_Calls()));
    final column = tester.getTopLeft(find.text('host')).dx;
    for (final label in [
      'Open In File Manager',
      'feature/workspace-details',
      'Compare against origin/main',
      '#123: Add Workspace Details',
      'Open',
      'Commit, Push & Create PR',
      'Changes',
    ]) {
      expect(tester.getTopLeft(find.text(label)).dx, column, reason: label);
    }
    expect(
      tester.getCenter(find.byTooltip('host Options')).dx,
      tester.getCenter(find.byTooltip('Commit, Push & Create PR Options')).dx,
    );
  });

  testWidgets('keyboard reaches row and menu segments and activates them', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_card(calls));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls.pressed, ['host', 'host-menu']);
  });

  testWidgets('busy rows keep a disabled menu segment in place', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_card(calls));
    Finder branchSegment() => find
        .ancestor(
          of: find.text('feature/workspace-details'),
          matching: find.byType(AleraWorkspaceDetailSegment),
        )
        .first;
    final idle = tester.getSize(branchSegment()).width;
    await tester.pumpWidget(_card(calls, running: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Pushing Options'), findsOneWidget);
    await tester.tap(find.byTooltip('Pushing Options'));
    await tester.tap(find.text('feature/workspace-details'));
    expect(calls.pressed, isEmpty);
    expect(tester.getSize(branchSegment()).width, idle);
  });

  testWidgets('long names truncate to one line at the minimum width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(_Calls(), width: AleraTokens.workspaceDetailsMinWidth, long: true),
    );
    expect(tester.takeException(), isNull);
    final branch = tester.widget<Text>(find.text(_longBranch));
    expect(branch.maxLines, 1);
    expect(branch.overflow, TextOverflow.ellipsis);
    expect(find.byTooltip(_longBranch), findsOneWidget);
    expect(
      tester.getSize(find.text(_longTitle)).height,
      lessThanOrEqualTo(
        tester.getSize(find.text('Open In File Manager')).height * 2,
      ),
    );
  });

  testWidgets(
    'pending PR keeps its state and action readable at minimum width',
    (tester) async {
      await tester.pumpWidget(_card(_Calls(), pending: true));
      final stateWidth = tester.getSize(find.text('Open')).width;
      final actionWidth = tester.getSize(find.text('Merging…')).width;
      await tester.pumpWidget(
        _card(
          _Calls(),
          pending: true,
          width: AleraTokens.workspaceDetailsMinWidth,
        ),
      );
      expect(tester.getSize(find.text('Open')).width, stateWidth);
      expect(tester.getSize(find.text('Merging…')).width, actionWidth);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('essential density keeps the host on the options row', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_card(calls, density: .essential));
    expect(find.text('Open In File Manager'), findsNothing);
    await tester.tap(find.byTooltip('Workspace Options'));
    expect(calls.pressed, ['options']);
    expect(find.text('Compare against origin/main'), findsNothing);
    expect(find.text('Changes'), findsOneWidget);
  });

  for (final (name, density, width, long, running, error, critical, pending)
      in <
        (
          String,
          WorkspaceDetailsDensity,
          double,
          bool,
          bool,
          String?,
          bool,
          bool,
        )
      >[
        (
          'full',
          .full,
          AleraTokens.workspaceDetailsWidth,
          false,
          false,
          null,
          false,
          false,
        ),
        (
          'long-min-width',
          .full,
          AleraTokens.workspaceDetailsMinWidth,
          true,
          false,
          null,
          true,
          false,
        ),
        (
          'progress-min-width',
          .full,
          AleraTokens.workspaceDetailsMinWidth,
          true,
          true,
          null,
          false,
          true,
        ),
        (
          'progress',
          .full,
          AleraTokens.workspaceDetailsWidth,
          false,
          true,
          null,
          false,
          true,
        ),
        (
          'error',
          .full,
          AleraTokens.workspaceDetailsWidth,
          false,
          false,
          'Push rejected: the remote branch moved.',
          false,
          false,
        ),
        (
          'compact',
          .compact,
          AleraTokens.workspaceDetailsWidth,
          true,
          false,
          null,
          false,
          false,
        ),
        (
          'essential',
          .essential,
          AleraTokens.workspaceDetailsWidth,
          false,
          false,
          null,
          false,
          false,
        ),
      ]) {
    testWidgets('renders the $name state without overflow', (tester) async {
      final capture = GlobalKey();
      await tester.pumpWidget(
        _card(
          _Calls(),
          density: density,
          width: width,
          long: long,
          running: running,
          error: error,
          critical: critical,
          pending: pending,
          capture: capture,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await _save(tester, capture, name);
    });
  }

  testWidgets('keyboard focus draws a ring on the focused segment', (
    tester,
  ) async {
    final capture = GlobalKey();
    await tester.pumpWidget(_card(_Calls(), capture: capture));
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(
        of: find.byTooltip('feature/workspace-details Options'),
        matching: find.byWidget(focused.widget),
      ),
      findsOneWidget,
    );
    await _save(tester, capture, 'focus');
  });
}
