import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_composer_draft_store.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_composer_draft.dart';
import 'package:alera_mobile/src/features/codex_chat/presentation/mobile_codex_chat_screen.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/fake_mobile_codex_client.dart';

part 'mobile_codex_chat_widget_foundation_test_cases.dart';
part 'mobile_codex_chat_widget_catalog_test_cases.dart';
part 'mobile_codex_chat_widget_model_menu_test_cases.dart';
part 'mobile_codex_chat_widget_viewer_test_cases.dart';
part 'mobile_codex_chat_widget_timeline_test_cases.dart';
part 'mobile_codex_chat_widget_turn_activity_test_cases.dart';
part 'mobile_codex_chat_widget_file_change_test_cases.dart';
part 'mobile_codex_chat_widget_tool_response_test_cases.dart';
part 'mobile_codex_chat_widget_plan_parity_test_cases.dart';
part 'mobile_codex_chat_widget_request_test_cases.dart';
part 'mobile_codex_chat_widget_session_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_2_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_3_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_4_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_5_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_6_test_cases.dart';
part 'mobile_codex_chat_widget_review_regression_7_test_cases.dart';
part 'mobile_codex_chat_widget_review_transition_test_cases.dart';
part 'mobile_codex_chat_widget_review_dialog_test_cases.dart';
part 'mobile_codex_chat_widget_goal_test_cases.dart';

void main() {
  _registerMobileCodexFoundationTests();
  _registerMobileCodexCatalogTests();
  _registerMobileCodexModelMenuTests();
  _registerMobileCodexViewerTests();
  _registerMobileCodexTimelineTests();
  _registerMobileCodexTurnActivityTests();
  _registerMobileCodexFileChangeTests();
  _registerMobileCodexToolResponseTests();
  _registerMobileCodexPlanParityTests();
  _registerMobileCodexRequestTests();
  _registerMobileCodexSessionTests();
  _registerMobileCodexReviewRegressionTests();
  _registerMobileCodexReviewRegression2Tests();
  _registerMobileCodexReviewRegression3Tests();
  _registerMobileCodexReviewRegression4Tests();
  _registerMobileCodexReviewRegression5Tests();
  _registerMobileCodexReviewRegression6Tests();
  _registerMobileCodexReviewRegression7Tests();
  _registerMobileCodexReviewTransitionTests();
  _registerMobileCodexReviewDialogTests();
  _registerMobileCodexGoalTests();
  testWidgets('mobile Codex chat phone golden', (tester) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, client: client, hostId: 'host-phone');
    await expectLater(
      find.byType(MobileCodexChatScreen),
      matchesGoldenFile('goldens/codex_chat_phone.png'),
    );
  });

  testWidgets('mobile disables Codex shimmer for reduced motion', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-1',
        'timelineCells': <Object?>[],
      },
    );
    addTearDown(client.dispose);

    await _pumpScreen(tester, client: client, hostId: 'host-reduced-motion');
    final workingShimmer = find.ancestor(
      of: find.text('Working'),
      matching: find.byType(ShaderMask),
    );
    expect(workingShimmer, findsOneWidget);

    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-reduced-motion',
      disableAnimations: true,
    );

    expect(workingShimmer, findsNothing);
  });

  testWidgets('mobile Codex chat tablet golden', (tester) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, client: client, hostId: 'host-tablet');
    await expectLater(
      find.byType(MobileCodexChatScreen),
      matchesGoldenFile('goldens/codex_chat_tablet.png'),
    );
  });
}

class _UnavailableUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

class _LaunchWithoutQueryUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  var launches = 0;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches += 1;
    return true;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required MobileCodexClient client,
  required String hostId,
  String? tabId,
  ProviderContainer? container,
  bool disableAnimations = false,
  void Function(String workspaceId, String tabId)? onFocusBoundTab,
}) async {
  final child = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: .dark(),
    home: MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: disableAnimations),
      child: Scaffold(
        body: MobileCodexChatScreen(
          hostId: hostId,
          tabId: tabId ?? 'tab-$hostId',
          workspaceId: 'workspace-$hostId',
          onFocusBoundTab: onFocusBoundTab,
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(
            overrides: [
              mobileCodexClientProvider(hostId)
                  .overrideWith((ref) async => client),
            ],
            child: child,
          )
        : UncontrolledProviderScope(container: container, child: child),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
}
