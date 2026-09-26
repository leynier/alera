import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_page.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';
import '../support/workflow_cleanup_catalog_fixture.dart';

void main() {
  testWidgets(
    'resource selection previews before applying and releases its watcher',
    (tester) async {
      final repository = _Repository();
      addTearDown(repository.transport.events.close);
      String? selected;
      await tester.pumpWidget(
        _page(repository, onSelected: (id) => selected = id),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('Workflow Resources'), findsOneWidget);
      expect(repository.transport.events.hasListener, true);
      await tester.ensureVisible(find.byType(AleraCheckbox).first);
      await tester.tap(find.byType(AleraCheckbox).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review Cleanup'));
      await tester.tap(find.text('Review Cleanup'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(repository.applied, false);
      expect(selected, isNotNull);
      expect(find.text('Review Cleanup'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(AleraCheckbox),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(AleraCheckbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Clean Selected Resources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clean Selected Resources'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(repository.applied, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(repository.transport.events.hasListener, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported cleanup host has an explicit way back to the run', (
    tester,
  ) async {
    final repository = _Repository()..unsupported = true;
    addTearDown(repository.transport.events.close);
    var back = 0;
    await tester.pumpWidget(_page(repository, onBack: () => back++));
    await tester.pumpAndSettle();
    expect(find.text('Update Required'), findsOneWidget);
    await tester.tap(find.text('Back To Run'));
    expect(back, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _page(
  _Repository repository, {
  ValueChanged<String?>? onSelected,
  VoidCallback? onBack,
}) => ProviderScope(
  overrides: [
    workflowLifecycleRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(
    theme: aleraDarkTheme,
    home: Scaffold(
      body: WorkflowCleanupPage(
        runId: 'run',
        allowPrepare: true,
        onBack: onBack ?? () {},
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);

class _Repository extends WorkflowLifecycleRepository {
  _Repository() : this._(_Client());
  _Repository._(this.transport) : super(transport, _Signer());
  final _Client transport;
  String id = 'cleanup';
  bool applied = false;
  bool unsupported = false;
  @override
  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload,
  ) async {
    if (unsupported) throw const WorkflowLifecycleUpdateRequired();
    switch (verb) {
      case 'workflows.cleanupResources':
        return cleanupResourcesFixture();
      case 'workflows.cleanups':
        return cleanupHistoryFixture(empty: true);
      case 'workflows.previewCleanup':
        id =
            (jsonDecode(payload['document']! as String) as Map)['id'] as String;
        return cleanupPreviewFixture()..['id'] = id;
      case 'workflows.applyCleanup':
        applied = true;
        expect(payload.keys.toSet(), {'id', 'digest'});
        break;
      case 'workflows.cleanupStatus':
        break;
      default:
        throw StateError('Unexpected request: $verb');
    }
    final status = cleanupStatusFixture(applied ? 'retired' : 'preview');
    (status['preview']! as Map)['id'] = id;
    return status;
  }
}

class _Client implements RuntimeHostClient {
  final events = StreamController<RuntimeHostEvent>.broadcast();
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Signer implements WorkflowDecisionSigner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
