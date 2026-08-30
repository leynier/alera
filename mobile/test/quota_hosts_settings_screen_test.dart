import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/application/quota_host_visibility_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quotas_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/home_quotas_section.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_hosts_settings_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:alera_mobile/src/features/settings/presentation/app_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('settings select local and cloud hosts without connecting', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        availableHostsProvider.overrideWith(() => _TestAvailableHosts(_hosts)),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container, const AppSettingsScreen());
    await tester.tap(find.text('Quota Hosts'));
    await tester.pumpAndSettle();

    expect(find.text('Work Laptop'), findsOneWidget);
    expect(find.text('Cloud Desktop'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(_switch('Work Laptop')).value, isTrue);
    await tester.tap(_switch('Work Laptop'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(_switch('Work Laptop')).value,
      isFalse,
    );
    await tester.tap(_switch('Cloud Desktop'));
    await tester.pumpAndSettle();
    expect(container.read(quotaHostVisibilityControllerProvider).requireValue, {
      'runtime-local',
      'runtime-cloud',
    });
  });

  testWidgets('home filters before subscribing and restores hidden quotas', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      quotaHiddenRuntimeIdsKey: ['runtime-local'],
    });
    final quotaReads = <String>[];
    final settingsReads = <String>[];
    final container = _quotaContainer(quotaReads, settingsReads);
    addTearDown(container.dispose);
    await _pump(tester, container, _home(_hosts));

    expect(find.text('Work Laptop'), findsNothing);
    expect(find.text('Cloud Desktop'), findsOneWidget);
    expect(quotaReads, ['cloud-profile']);
    expect(settingsReads, ['cloud-profile']);

    await tester.tap(find.text('Choose Hosts'));
    await tester.pumpAndSettle();
    await tester.tap(_switch('Work Laptop'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Work Laptop'), findsOneWidget);
    expect(quotaReads, contains('local-profile'));

    // Explicit per-host quota screens are independent of Home visibility.
    await container
        .read(quotaHostVisibilityControllerProvider.notifier)
        .setHostVisible('runtime-local', false);
    await _pump(tester, container, AgentQuotasScreen(host: _hosts.first));
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets(
    'all hidden keeps the selector and newly added hosts are visible',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        quotaHiddenRuntimeIdsKey: ['runtime-local', 'runtime-cloud'],
      });
      final quotaReads = <String>[];
      final settingsReads = <String>[];
      final container = _quotaContainer(quotaReads, settingsReads);
      addTearDown(container.dispose);
      await _pump(tester, container, _home(_hosts));

      expect(find.text('Choose Hosts'), findsOneWidget);
      expect(find.textContaining('No hosts selected.'), findsOneWidget);
      expect(quotaReads, isEmpty);
      expect(settingsReads, isEmpty);

      await _pump(
        tester,
        container,
        _home([
          _hosts.first.withAlias('Renamed Laptop'),
          _hosts.last,
          _host('new-profile', 'runtime-new', 'New Host'),
        ]),
      );
      expect(find.text('Renamed Laptop'), findsNothing);
      expect(find.text('New Host'), findsOneWidget);
      expect(quotaReads, ['new-profile']);
    },
  );

  testWidgets('does not poll quotas while the saved selection loads', (
    tester,
  ) async {
    final selection = Completer<Set<String>>();
    final quotaReads = <String>[];
    final container = ProviderContainer(
      overrides: [
        quotaHostVisibilityControllerProvider.overrideWith(
          () => _DelayedVisibility(selection.future),
        ),
        agentQuotaControllerProvider.overrideWith2((_) => _Quotas(quotaReads)),
        hostSettingsControllerProvider.overrideWith2((_) => _Settings([])),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container, _home(_hosts));
    expect(quotaReads, isEmpty);

    selection.complete({'runtime-local'});
    await tester.pumpAndSettle();
    expect(quotaReads, ['cloud-profile']);
  });

  testWidgets(
    'selection read failure does not poll all hosts and offers retry',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        quotaHiddenRuntimeIdsKey: 42,
      });
      final quotaReads = <String>[];
      final container = _quotaContainer(quotaReads, []);
      addTearDown(container.dispose);
      await _pump(tester, container, _home(_hosts));
      expect(quotaReads, isEmpty);
      expect(find.text('Could not load quota hosts.'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(quotaHiddenRuntimeIdsKey, ['runtime-local']);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(quotaReads, ['cloud-profile']);
    },
  );

  testWidgets('empty host list explains how to add a source', (tester) async {
    final container = ProviderContainer(
      overrides: [
        availableHostsProvider.overrideWith(() => _TestAvailableHosts([])),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container, const QuotaHostsSettingsScreen());
    expect(
      find.text('Pair a host or sign in to choose quota hosts.'),
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('failed save keeps the selected host and shows an error', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        availableHostsProvider.overrideWith(() => _TestAvailableHosts(_hosts)),
        quotaHostVisibilityControllerProvider.overrideWith(
          _FailedSaveVisibility.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container, const QuotaHostsSettingsScreen());
    await tester.tap(_switch('Work Laptop'));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(_switch('Work Laptop')).value, isTrue);
    expect(find.text('Could not save quota hosts. Try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _switch(String name) => find.widgetWithText(SwitchListTile, name);

Widget _home(List<PairedHostProfile> hosts) => Scaffold(
  body: SingleChildScrollView(child: HomeQuotasSection(hosts: hosts)),
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAleraMobileDarkTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _quotaContainer(
  List<String> quotaReads,
  List<String> settingsReads,
) {
  return ProviderContainer(
    overrides: [
      availableHostsProvider.overrideWith(() => _TestAvailableHosts(_hosts)),
      agentQuotaControllerProvider.overrideWith2((_) => _Quotas(quotaReads)),
      hostConnectionControllerProvider.overrideWith2(
        (_) => _PendingConnection(),
      ),
      hostSettingsControllerProvider.overrideWith2(
        (_) => _Settings(settingsReads),
      ),
    ],
  );
}

final _hosts = [
  _host('local-profile', 'runtime-local', 'Laptop').withAlias('Work Laptop'),
  _host('cloud-profile', 'runtime-cloud', 'Cloud Desktop', remote: true),
];

PairedHostProfile _host(
  String id,
  String runtimeId,
  String name, {
  bool remote = false,
}) {
  return PairedHostProfile(
    id: id,
    runtimeId: runtimeId,
    displayName: name,
    endpoint: remote ? 'relay://$runtimeId' : 'ws://127.0.0.1:6768',
    deviceId: 'device-1',
    pairedAt: .utc(2026),
    isRemote: remote,
  );
}

class _TestAvailableHosts(final List<PairedHostProfile> hosts)
    extends AvailableHosts {
  @override
  Future<List<PairedHostProfile>> build() async => hosts;
}

class _Quotas(final List<String> reads) extends AgentQuotaController {
  @override
  Future<QuotaSnapshotState> build(String hostId) async {
    reads.add(hostId);
    return QuotaSnapshotState.fromJson({
      'snapshots': [
        {'provider': 'codex', 'status': 'ok'},
      ],
    });
  }
}

class _Settings(final List<String> reads) extends HostSettingsController {
  @override
  Future<PortableHostSettings> build(String hostId) async {
    reads.add(hostId);
    return PortableHostSettings.fromJson({});
  }
}

class _DelayedVisibility(final Future<Set<String>> selection)
    extends QuotaHostVisibilityController {
  @override
  Future<Set<String>> build() => selection;
}

class _FailedSaveVisibility extends QuotaHostVisibilityController {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<void> setHostVisible(String runtimeId, bool visible) async {
    throw StateError('Storage unavailable');
  }
}

class _PendingConnection extends HostConnectionController {
  @override
  Future<MobileRuntimeClient> build(String hostId) =>
      Completer<MobileRuntimeClient>().future;
}
