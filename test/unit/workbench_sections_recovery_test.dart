import 'dart:async';

import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sections follow runtime capability changes without another bootstrap',
    () async {
      final client = _Client();
      final container = _container(client);
      final controller = container.read(workbenchControllerProvider.notifier);
      await controller.bootstrap();
      await _until(() => client.checks > 0);
      expect(controller.state.supportsSections, isFalse);
      expect(client.lists, 0);
      expect(controller.state.viewPrefs.collapsedSectionIds, {'section'});

      client.supported = true;
      client.events.add(
        const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}),
      );
      await _until(() => controller.state.supportsSections);
      expect(controller.state.sections.single.id, 'section');
      expect(client.lists, 1);
      controller.setGroupBy(WorkbenchGroupBy.section);

      client.supported = false;
      client.events.add(
        const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}),
      );
      await _until(() => !controller.state.supportsSections);
      expect(controller.state.sections, isEmpty);
      expect(controller.state.viewPrefs.groupBy, WorkbenchGroupBy.project);
      expect(controller.state.viewPrefs.collapsedSectionIds, {'section'});
      expect(client.lists, 1);
    },
  );

  test('section capability checks recover after transient failure without an event', () async {
    final client = _Client()
      ..supported = true
      ..failNextCheck = true;
    final container = _container(client);
    final controller = container.read(workbenchControllerProvider.notifier);
    await controller.bootstrap();
    expect(controller.state.bootstrapped, isTrue);
    await _until(() => controller.state.supportsSections);
    expect(client.checks, greaterThanOrEqualTo(2));
    expect(controller.state.sections.single.name, 'Work');
  });
}

ProviderContainer _container(_Client client) {
  final container = ProviderContainer(
    overrides: [
      workbenchRepositoryProvider.overrideWithValue(
        RuntimeWorkbenchRepository(client),
      ),
      projectsServiceProvider.overrideWithValue(_Services()),
      workbenchViewPrefsRepositoryProvider.overrideWithValue(_Prefs()),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await pumpEventQueue();
    expect(client.events.hasListener, isFalse);
    await client.events.close();
  });
  return container;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = false;
  bool failNextCheck = false;
  int checks = 0;
  int lists = 0;
  final events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    checks++;
    if (failNextCheck) {
      failNextCheck = false;
      throw StateError('Connection interrupted');
    }
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    expect(type, 'workspaceSection.list');
    lists++;
    return [
      {
        'id': 'section',
        'name': 'Work',
        'createdAt': '2026-08-30T00:00:00Z',
        'updatedAt': '2026-08-30T00:00:00Z',
      },
    ];
  }
}

class _Projects implements ProjectRepository {
  @override
  Future<List<Project>> listAll() async => [];
  @override
  Stream<List<Project>> watchAll() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Services implements ProjectsService {
  @override
  final projectRepository = _Projects();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Prefs implements WorkbenchViewPrefsRepository {
  @override
  Future<WorkbenchViewPrefs> load() async =>
      WorkbenchViewPrefs.defaults.copyWith(collapsedSectionIds: {'section'});
  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {}
  @override
  Stream<WorkbenchViewPrefs> get changes => const Stream.empty();
}
