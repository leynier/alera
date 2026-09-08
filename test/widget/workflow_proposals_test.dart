import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_new_run_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_proposal_page.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_saved_proposals.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';

void main() {
  testWidgets(
    'proposal cancellation confirms and retries without restarting a coordinator',
    (tester) async {
      final client = _Client();
      addTearDown(client.events.close);
      var fail = true;
      String? cancellation;
      client.read = () async {
        if (client.calls.last == 'workflows.cancelProposal') {
          if (fail) throw StateError('Response lost');
          cancellation = 'pending';
          return {'status': cancellation};
        }
        return {
          'id': 'proposal',
          if (cancellation != null) 'cancellation': {'status': cancellation},
        };
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workflowLifecycleRepositoryProvider.overrideWithValue(
              WorkflowLifecycleRepository(client, client),
            ),
          ],
          child: MaterialApp(
            theme: aleraDarkTheme,
            home: Scaffold(
              body: WorkflowProposalPage(
                id: 'proposal',
                onBack: () {},
                onOpenRun: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Proposal'));
      await tester.pumpAndSettle();
      expect(client.calls, ['workflows.proposalStatus']);
      await tester.tap(find.text('Keep Proposal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Proposal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Cancellation'));
      await tester.pumpAndSettle();
      expect(find.text('Start Coordinator'), findsNothing);
      fail = false;
      await tester.tap(find.text('Retry Cancellation'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelling Proposal'), findsOneWidget);
      expect(find.text('Proposal Cancelled'), findsNothing);
      cancellation = 'settled';
      await tester.tap(find.text('Refresh Proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Proposal Cancelled'), findsOneWidget);
      expect(find.text('Start Coordinator'), findsNothing);
      final cancellations = [
        for (var i = 0; i < client.calls.length; i++)
          if (client.calls[i] == 'workflows.cancelProposal') client.payloads[i],
      ];
      expect(cancellations, [
        {'id': 'proposal'},
        {'id': 'proposal'},
      ]);
      expect(client.calls.contains('workflows.startCoordinator'), isFalse);
    },
  );
  testWidgets('opening saved proposals retains the unsaved objective', (
    tester,
  ) async {
    final client = _Client();
    addTearDown(client.events.close);
    client.read = () async => switch (client.calls.last) {
      'workflows.source' => {'sha': 'a' * 40, 'hasUncommittedChanges': true},
      'workflows.catalog' => {
        'entries': [
          {
            'name': 'Quick Fix',
            'source': {'origin': 'builtIn', 'id': 'quick-fix'},
          },
        ],
      },
      'workflows.recipe' => {
        'recipe': {'description': 'Make a focused correction.', 'roles': []},
      },
      _ => client.response,
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowLifecycleRepositoryProvider.overrideWithValue(
            WorkflowLifecycleRepository(client, client),
          ),
          workflowCatalogRepositoryProvider.overrideWithValue(
            WorkflowCatalogRepository(client),
          ),
          agentProfilesProvider.overrideWith(_Profiles.new),
          workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: Scaffold(
            body: WorkflowNewRunPage(onCreated: (_) {}, onBack: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<AleraDropdownField<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AleraDropdownField<String> &&
                widget.labelText == 'Project / Workspace',
          ),
        )
        .onChanged('ws-2');
    await tester.pumpAndSettle();
    tester
        .widget<AleraDropdownField<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AleraDropdownField<String> &&
                widget.labelText == 'Recipe',
          ),
        )
        .onChanged('builtIn::quick-fix');
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, 'Preserve this workflow objective.');
    await tester.tap(find.text('Saved Proposals'));
    await tester.pumpAndSettle();
    expect(find.text('There are no saved proposals yet.'), findsOneWidget);
    await tester.tap(find.text('New Proposal'));
    await tester.pumpAndSettle();
    expect(find.text('Preserve this workflow objective.'), findsOneWidget);
    expect(client.calls, [
      'workflows.source',
      'workflows.catalog',
      'workflows.recipe',
      'workflows.proposals',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved proposals page lazily without launching coordinators', (
    tester,
  ) async {
    final client = _Client()
      ..response = {
        'entries': [_entry('first')],
        'hasMore': true,
      };
    addTearDown(client.events.close);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: WorkflowSavedProposals(
            repository: WorkflowLifecycleRepository(client, client),
            onSelect: (id) => selected = id,
            onNew: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.calls, ['workflows.proposals']);
    client.response = {
      'entries': [_entry('first'), _entry('second')],
      'hasMore': false,
    };
    await tester.tap(find.text('Load More Proposals'));
    await tester.pumpAndSettle();
    expect(client.payloads.last, {
      'beforeCreatedAt': '2026-09-07T12:00:00Z',
      'beforeId': 'first',
    });
    expect(find.text('Objective first'), findsOneWidget);
    expect(find.text('Load More Proposals'), findsNothing);
    await tester.tap(find.text('Objective second'));
    expect(selected, 'second');
    expect(client.calls, ['workflows.proposals', 'workflows.proposals']);
    await tester.pump(const Duration(minutes: 1));
    expect(client.calls.length, 2);
  });

  testWidgets('a late proposal read cannot replace a refreshed prepared plan', (
    tester,
  ) async {
    final first = Completer<Object?>();
    final second = Completer<Object?>();
    final client = _Client();
    client.read = () => client.calls.length == 1 ? first.future : second.future;
    addTearDown(client.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowLifecycleRepositoryProvider.overrideWithValue(
            WorkflowLifecycleRepository(client, client),
          ),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: Scaffold(
            body: WorkflowProposalPage(
              id: 'proposal',
              onBack: () {},
              onOpenRun: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.events.hasListener, isTrue);
    await tester.tap(find.text('Refresh Proposal'));
    await tester.pump();
    second.complete({'id': 'proposal', 'runId': 'prepared-run'});
    await tester.pumpAndSettle();
    expect(find.text('Open Prepared Run'), findsOneWidget);
    first.complete({'id': 'proposal'});
    await tester.pumpAndSettle();
    expect(find.text('Open Prepared Run'), findsOneWidget);
    expect(find.text('Start Coordinator'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(client.events.hasListener, isFalse);
    expect(client.calls, [
      'workflows.proposalStatus',
      'workflows.proposalStatus',
    ]);
  });
}

Map<String, Object?> _entry(String id) => {
  'id': id,
  'objective': 'Objective $id',
  'workspaceName': 'Source Workspace',
  'createdAt': '2026-09-07T12:00:00Z',
};

class _Profiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => [];
}

class _Client
    implements
        RuntimeHostClient,
        RuntimeHostCapabilityClient,
        WorkflowDecisionSigner {
  @override
  Future<Uint8List> sign(String statementJson) async =>
      throw UnimplementedError();
  final calls = <String>[];
  final events = StreamController<RuntimeHostEvent>.broadcast();
  Future<Object?> Function()? read;
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;
  final payloads = <Map<String, Object?>>[];
  Map<String, Object?> response = {'entries': <Object?>[], 'hasMore': false};
  @override
  Future<bool> supportsRuntimeCapability(String capability) async => true;
  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(verb);
    payloads.add(payload);
    return read == null ? response : await read!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
