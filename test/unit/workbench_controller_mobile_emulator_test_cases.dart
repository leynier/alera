part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerMobileEmulatorTests() {
  test(
    'opens one persisted emulator tab in a right split and then reuses it',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final originalGroupId = _controller.state
          .layoutFor(workspace.id)!
          .activeGroupId;

      final opened = await _controller.openMobileEmulatorTab(
        workspace: workspace,
        platform: .android,
        deviceId: 'android:Pixel_9',
        targetGroupId: originalGroupId,
      );
      await _flush();

      final layout = _controller.state.layoutFor(workspace.id)!;
      expect(opened.kind, WorkspaceTabKind.mobileEmulator);
      expect(opened.mobileEmulator?.platform, MobileEmulatorPlatform.android);
      expect(opened.mobileEmulator?.deviceId, 'android:Pixel_9');
      expect(layout.root.axis, WorkbenchSplitAxis.horizontal);
      expect(layout.root.first?.groupId, originalGroupId);
      expect(layout.root.second?.groupId, layout.groupIdForTab(opened.id));
      expect(layout.activeTabId, opened.id);
      expect(_harness.emulatorRuntimeClient.attachRequests, 1);

      final reused = await _controller.openMobileEmulatorTab(
        workspace: workspace,
        targetGroupId: originalGroupId,
      );

      expect(reused.id, opened.id);
      expect(_harness.emulatorRuntimeClient.attachRequests, 1);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.kind == WorkspaceTabKind.mobileEmulator),
        hasLength(1),
      );
    },
  );

  test('repairs the layout for an existing hidden emulator tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final previousTabs = _controller.state.tabsFor(workspace.id);
    final originalLayout = _controller.state.layoutFor(workspace.id)!;
    final now = DateTime.utc(2026, 7, 27);
    final emulatorTab = WorkspaceTabRecord(
      id: 'persisted-emulator-tab',
      workspaceId: workspace.id,
      kind: .mobileEmulator,
      title: 'Pixel 9',
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{
        workspaceTabMobileEmulatorPayloadKey:
            const WorkspaceMobileEmulatorPayload(
              platform: .android,
              deviceId: 'android:Pixel_9',
            ).toJson(),
      },
    );
    _controller.state = _controller.state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ..._controller.state.tabsByWorkspace,
        workspace.id: <WorkspaceTabRecord>[...previousTabs, emulatorTab],
      },
    );

    expect(originalLayout.groupIdForTab(emulatorTab.id), isNull);

    final opened = await _controller.openMobileEmulatorTab(
      workspace: workspace,
      targetGroupId: originalLayout.activeGroupId,
    );

    final repairedLayout = _controller.state.layoutFor(workspace.id)!;
    expect(opened.id, emulatorTab.id);
    expect(repairedLayout.root.axis, WorkbenchSplitAxis.horizontal);
    expect(
      repairedLayout.root.second?.groupId,
      repairedLayout.groupIdForTab(emulatorTab.id),
    );
    expect(repairedLayout.activeTabId, emulatorTab.id);
    expect(_harness.emulatorRuntimeClient.attachRequests, 0);
  });

  test('keeps the emulator lease when closing its tab fails', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = await _controller.openMobileEmulatorTab(
      workspace: workspace,
      platform: .android,
      deviceId: 'android:Pixel_9',
    );
    final leases = _harness.container.read(
      mobileEmulatorLeaseCoordinatorProvider,
    );
    await leases.acquire(
      MobileEmulatorTarget(tabId: tab.id, workspaceId: workspace.id),
    );
    _harness.workbenchRepository.removeWorkspaceTabError = StateError(
      'close failed',
    );

    await expectLater(
      _controller.closeWorkspaceTab(workspace: workspace, tabId: tab.id),
      throwsStateError,
    );
    await leases.suspend(tab.id);

    expect(_harness.emulatorRuntimeClient.releaseRequests, 1);
    expect(
      _controller.state.tabsFor(workspace.id).map((candidate) => candidate.id),
      contains(tab.id),
    );
  });
}

class _FakeWorkbenchEmulatorRuntimeClient implements RuntimeHostClient {
  int attachRequests = 0;
  int releaseRequests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'status.get') {
      return <String, Object?>{
        'runtimeCapabilities': const <String>[
          aleraRuntimeHostMobileEmulatorCapability,
        ],
      };
    }
    if (type == 'emulator.acquire' || type == 'emulator.release') {
      if (type == 'emulator.release') {
        releaseRequests += 1;
      }
      return <String, Object?>{
        'ok': true,
        'session': <String, Object?>{
          'id': payload['tabId'],
          'state': type == 'emulator.release' ? 'parked' : 'ready',
          'platform': 'android',
          'deviceId': 'android:Pixel_9',
        },
      };
    }
    if (type != 'emulator.attach') {
      throw StateError('Unexpected emulator request: $type');
    }
    attachRequests += 1;
    final workspaceId = payload['workspaceId']! as String;
    final platform = payload['platform']! as String;
    final deviceId = payload['deviceId']! as String;
    final now = DateTime.utc(2026, 7, 27);
    return <String, Object?>{
      'ok': true,
      'tab': <String, Object?>{
        'id': 'emulator-tab',
        'workspaceId': workspaceId,
        'kind': 'mobileEmulator',
        'title': 'Pixel 9',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'payload': <String, Object?>{
          workspaceTabMobileEmulatorPayloadKey: <String, Object?>{
            'schemaVersion': 1,
            'platform': platform,
            'deviceId': deviceId,
          },
        },
      },
      'session': <String, Object?>{
        'id': 'emulator-tab',
        'state': 'parked',
        'platform': platform,
        'deviceId': deviceId,
      },
    };
  }
}
