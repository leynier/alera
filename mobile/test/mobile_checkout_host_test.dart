import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_checkout_selection.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_checkout_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/fake_workspace_hosts_client.dart';

void main() {
  test(
    'SSH creation refuses paired-device uploads before creating a task',
    () async {
      final client = _CheckoutClient();
      addTearDown(client.dispose);
      const request = PromptWorkspaceCreateRequest(
        hostId: 'paired',
        checkoutHostId: 'ssh-box',
        projectId: 'project',
        prompt: 'Read /paired/prompt-files/spec.pdf',
        localAttachmentPaths: {'/paired/prompt-files/spec.pdf'},
        sourceBranch: '',
        profileId: 'profile-1',
        workspaceBranches: {},
        useProjectCheckout: true,
      );
      await expectLater(
        runPromptWorkspaceCreate(
          client: client,
          loadTerminalClient: () async => client,
          request: request,
          clientMutationId: 'blocked-upload',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('paired device'),
          ),
        ),
      );
      expect(client.calls, isEmpty);
      expect(client.sharedHost, isNull);
      expect(client.branchHosts, isEmpty);
    },
  );

  testWidgets('retry attachments index the saved SSH checkout', (tester) async {
    final client = _CheckoutClient()..workspaceFiles = ['remote/task.dart'];
    addTearDown(client.dispose);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('paired').overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: CreateWorkspaceScreen(
            supportsSharedCheckoutWorkspaces: true,
            hostId: 'paired',
            initialCheckoutHostId: 'ssh-box',
            supportsWorkspaceFiles: true,
            supportsPromptImageUpload: true,
            supportsPromptFileUpload: true,
            projects: [
              ProjectSummary(
                id: 'project',
                name: 'Project',
                repoPath: '/local',
              ),
            ],
            workspaces: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CreateWorkspaceScreen)),
    );
    final attachments = promptLocalAttachmentsProvider('paired', const {});
    container.read(attachments.notifier).add('/paired/retained.pdf');
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(container.read(attachments), contains('/paired/retained.pdf'));
    await tester.tap(find.text('From Prompt'));
    await tester.pumpAndSettle();
    expect(find.text('Build Mac'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Add Attachment'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add Attachment'));
    await tester.pumpAndSettle();
    expect(find.text('Photo Library'), findsNothing);
    expect(find.text('Files'), findsNothing);
    await tester.tap(find.text('Workspace File'));
    await tester.pumpAndSettle();
    expect(client.quickOpenHost, 'ssh-box');
    await tester.tap(find.text('remote/task.dart'));
    await tester.pumpAndSettle();
    expect(client.stoppedQuickOpenSessions, hasLength(1));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
          .controller!
          .text,
      'remote/task.dart',
    );
  });

  testWidgets(
    'manual creation keeps the paired runtime and selects an SSH checkout',
    (tester) async {
      final client = _CheckoutClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('paired')
                .overrideWith((ref) async => client),
            terminalClientProvider('paired')
                .overrideWith((ref) async => client),
          ],
          child: const MaterialApp(
            home: CreateWorkspaceScreen(
              supportsSharedCheckoutWorkspaces: true,
              hostId: 'paired',
              initialFromPrompt: false,
              projects: [
                ProjectSummary(
                  id: 'project',
                  name: 'Project',
                  repoPath: '/local',
                ),
              ],
              workspaces: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paired Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build Mac'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create Another'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create Another'));
      await tester.scrollUntilVisible(
        find.text('Create Workspace'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();
      expect(client.sharedHost, 'ssh-box');
    },
  );

  testWidgets('host picker marks each checkout with its glyph and state', (
    tester,
  ) async {
    final client = _HostStatusCheckoutClient();
    addTearDown(client.dispose);
    await _pumpManualCreate(tester, client);
    expect(find.byIcon(AleraIcons.pairedDevices), findsOneWidget);
    await tester.tap(find.text('Paired Device'));
    await tester.pumpAndSettle();
    expect(find.byIcon(AleraIcons.pairedDevices), findsNWidgets(2));
    final expected = <String, (HostOs, bool)>{
      'Studio Mac (Update Available)': (HostOs.macos, true),
      'Build Box (Offline)': (HostOs.windows, true),
      'Rack (Needs Setup)': (HostOs.linux, false),
      'Attic (Installing…)': (HostOs.unknown, false),
      'Lab (Error)': (HostOs.linux, false),
    };
    for (final MapEntry(key: label, value: (os, enabled)) in expected.entries) {
      final entry = tester.widget<AleraDropdownEntry<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AleraDropdownEntry<String> && widget.label == label,
        ),
      );
      expect(entry.enabled, enabled, reason: label);
      expect((entry.leading! as AleraHostOsIcon).os, os, reason: label);
    }
  });

  testWidgets('a host without a runtime explains itself and blocks Create', (
    tester,
  ) async {
    final client = _HostStatusCheckoutClient();
    addTearDown(client.dispose);
    await _pumpManualCreate(tester, client, initialCheckoutHostId: 'ssh-tux');
    final blocked = tester.widget<Text>(
      find.text(
        'The Alera runtime is not installed on Rack. Set it up from the desktop.',
      ),
    );
    expect(blocked.style?.color, AleraTokens.error);
    expect(_createButton(tester).onPressed, isNull);

    await tester.tap(find.text('Rack (Needs Setup)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Box (Offline)').last);
    await tester.pumpAndSettle();
    final neutral = tester.widget<Text>(
      find.text('Alera connects to Build Box when the workspace needs it.'),
    );
    expect(neutral.style?.color, AleraTokens.foregroundMuted);
    expect(_createButton(tester).onPressed, isNotNull);
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();
    expect(client.sharedHost, 'ssh-win');
  });

  testWidgets('an older runtime without host status enables every host', (
    tester,
  ) async {
    final client = _HostStatusCheckoutClient()
      ..workspaceHosts = legacyWorkspaceHosts;
    addTearDown(client.dispose);
    await _pumpManualCreate(tester, client, initialCheckoutHostId: 'ssh-tux');
    expect(find.byKey(const Key('checkout-host-notice')), findsNothing);
    expect(_createButton(tester).onPressed, isNotNull);
    await tester.tap(find.text('Rack'));
    await tester.pumpAndSettle();
    final entries = tester.widgetList<AleraDropdownEntry<String>>(
      find.byType(AleraDropdownEntry<String>),
    );
    expect(entries.map((entry) => entry.label), [
      'Paired Device',
      'Studio Mac',
      'Build Box',
      'Rack',
      'Attic',
    ]);
    expect(entries.every((entry) => entry.enabled), isTrue);
  });

  test(
    'prompt branches, creation and retry identity use the checkout host',
    () async {
      final client = _CheckoutClient();
      addTearDown(client.dispose);
      const request = PromptWorkspaceCreateRequest(
        hostId: 'paired',
        checkoutHostId: 'ssh-box',
        projectId: 'project',
        prompt: 'Implement a task',
        localAttachmentPaths: {'/paired/removed-from-prompt.pdf'},
        sourceBranch: 'remote-only',
        profileId: 'profile-1',
        workspaceBranches: {},
      );
      final outcome = await runPromptWorkspaceCreate(
        client: client,
        loadTerminalClient: () async => client,
        request: request,
        clientMutationId: 'fixture-launch',
      );
      expect(client.branchHosts, ['ssh-box']);
      expect(client.managedHost, 'ssh-box');
      expect(client.managedSource, 'remote-only');
      final retry = request.withCreated(outcome.creation);
      expect(retry.hostId, 'paired');
      expect(retry.checkoutHostId, 'ssh-box');
      expect(retry.localAttachmentPaths, request.localAttachmentPaths);
      expect(request.matchesLaunchTarget(retry), isTrue);
      expect(
        request.matchesLaunchTarget(
          const PromptWorkspaceCreateRequest(
            hostId: 'paired',
            projectId: 'project',
            prompt: 'Implement a task',
            sourceBranch: 'remote-only',
            profileId: 'profile-1',
            workspaceBranches: {},
          ),
        ),
        isFalse,
      );
    },
  );
}

class _CheckoutClient extends FakeTerminalClient
    implements MobileCheckoutCatalogClient {
  String? sharedHost;
  String? managedHost;
  String? managedSource;
  String? quickOpenHost;
  final branchHosts = <String?>[];

  @override
  Future<MobileWorkspaceQuickOpenSession> startProjectCheckoutQuickOpen({
    required String projectId,
    String? checkoutHostId,
  }) {
    quickOpenHost = checkoutHostId;
    return super.startProjectCheckoutQuickOpen(
      projectId: projectId,
      checkoutHostId: checkoutHostId,
    );
  }

  @override
  Future<List<ProjectCheckoutSummary>> listProjectCheckouts(
    String projectId,
  ) async => const [
    ProjectCheckoutSummary(hostId: 'local', path: '/local'),
    ProjectCheckoutSummary(
      hostId: 'ssh-box',
      path: '/remote',
      hostName: 'Build Mac',
    ),
  ];

  @override
  Future<ProjectBranches> listBranches(
    String projectId, {
    String? checkoutHostId,
  }) async {
    branchHosts.add(checkoutHostId);
    final branches = checkoutHostId == 'ssh-box'
        ? ['remote-only']
        : ['local-only'];
    return ProjectBranches(
      projectId: projectId,
      branches: branches,
      localBranches: branches,
    );
  }

  @override
  Future<WorkspaceCreationResult> createSharedWorkspace({
    required String projectId,
    String? name,
    String? checkoutHostId,
    String? issueUrl,
  }) {
    sharedHost = checkoutHostId;
    return super.createSharedWorkspace(
      projectId: projectId,
      name: name,
      checkoutHostId: checkoutHostId,
    );
  }

  @override
  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? checkoutHostId,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
    String? issueUrl,
  }) {
    managedHost = checkoutHostId;
    managedSource = sourceBranch;
    return super.createManagedWorkspace(
      projectId: projectId,
      branch: branch,
      checkoutHostId: checkoutHostId,
      sourceBranch: sourceBranch,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
    );
  }
}

Future<void> _pumpManualCreate(
  WidgetTester tester,
  FakeTerminalClient client, {
  String? initialCheckoutHostId,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('paired').overrideWith((ref) async => client),
        terminalClientProvider('paired').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        home: CreateWorkspaceScreen(
          supportsSharedCheckoutWorkspaces: true,
          hostId: 'paired',
          initialFromPrompt: false,
          initialCheckoutHostId: initialCheckoutHostId,
          projects: const [
            ProjectSummary(id: 'project', name: 'Project', repoPath: '/local'),
          ],
          workspaces: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ButtonStyleButton _createButton(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Create Workspace'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

/// Lists a checkout on the paired device and on every host the runtime names.
class _HostStatusCheckoutClient extends FakeRemoteWorkspacesClient
    implements MobileCheckoutCatalogClient {
  _HostStatusCheckoutClient() {
    workspaceHosts = statusWorkspaceHosts;
  }

  String? sharedHost;

  @override
  Future<List<ProjectCheckoutSummary>> listProjectCheckouts(
    String projectId,
  ) async => [
    const ProjectCheckoutSummary(hostId: 'local', path: '/local'),
    for (final host in workspaceHosts)
      ProjectCheckoutSummary(
        hostId: host.id,
        path: '/remote/${host.id}',
        hostName: host.alias,
      ),
  ];

  @override
  Future<WorkspaceCreationResult> createSharedWorkspace({
    required String projectId,
    String? name,
    String? checkoutHostId,
    String? issueUrl,
  }) {
    sharedHost = checkoutHostId;
    return super.createSharedWorkspace(
      projectId: projectId,
      name: name,
      checkoutHostId: checkoutHostId,
    );
  }
}
