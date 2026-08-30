import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sentry/sentry.dart';
part 'terminal_host_client_resilience_cases.dart';
part 'terminal_host_client_timeout_cases.dart';
part 'terminal_host_client_binary_frames_cases.dart';
part 'terminal_host_client_protocol_mismatch_cases.dart';
part 'terminal_host_client_runtime_mutation_cases.dart';
part 'terminal_host_test_server.dart';

void main() {
  _registerTerminalHostClientResilienceTests();
  _registerTerminalHostClientTimeoutTests();
  _registerTerminalHostClientBinaryFrameTests();
  _registerTerminalHostClientProtocolMismatchTests();
  _registerTerminalHostClientRuntimeMutationTests();
  test('connects through launcher and sends lifecycle requests', () async {
    final tempDir = await Directory.systemTemp.createTemp('alera-host-client-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    final outputEvent = client.events
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    final exitEvent = client.events
        .where((event) => event is TerminalHostExitEvent)
        .cast<TerminalHostExitEvent>()
        .first;
    final errorEvent = client.events
        .where((event) => event is TerminalHostErrorEvent)
        .cast<TerminalHostErrorEvent>()
        .first;
    final pulseChangedEvent = client.events
        .where((event) => event is TerminalHostPulseChangedEvent)
        .cast<TerminalHostPulseChangedEvent>()
        .first;

    final attachment = await client.createOrAttach(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      workingDirectory: '/repo',
      launch: _launch(setupCommand: 'echo setup\n'),
      cols: 80,
      rows: 24,
    );
    expect(client.supportsTerminalRestart, isTrue);
    expect(client.supportsDeferredInput, isTrue);
    expect(client.supportsTerminalPulse, isTrue);
    final restarted = await client.restart(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      workingDirectory: '/repo',
      launch: _launch(setupCommand: 'echo setup\n'),
      cols: 80,
      rows: 24,
    );
    await client.write(sessionId: 'session-1', bytes: const <int>[]);
    await client.write(sessionId: 'session-1', bytes: const <int>[1, 2]);
    await client.write(
      sessionId: 'session-1',
      bytes: const <int>[3],
      deferredEnter: true,
    );
    await client.resize(sessionId: 'session-1', cols: 120, rows: 40);
    final pulseStatus = await client.terminalPulseStatus('session-1');
    final pulseConfiguration = const TerminalPulseConfiguration(
      command: 'R',
      appendEnter: false,
      delayMilliseconds: 2500,
    );
    final configuredPulse = await client.configureTerminalPulse(
      sessionId: 'session-1',
      configuration: pulseConfiguration,
      armed: true,
    );
    final resume = await client.setOutputPaused(
      sessionId: 'session-1',
      paused: false,
    );
    await client.detach('session-1');
    await client.terminate('session-1');

    server.send(<String, Object?>{
      'event': 'output',
      'payload': <String, Object?>{
        'sessionId': 'session-1',
        'dataBase64': encodeTerminalHostBytes(<int>[65]),
      },
    });
    server.send(<String, Object?>{
      'event': 'exit',
      'payload': <String, Object?>{'sessionId': 'session-1', 'exitCode': 7},
    });
    server.send(<String, Object?>{
      'event': 'error',
      'payload': <String, Object?>{'sessionId': 'session-1', 'error': 'boom'},
    });
    server.send(<String, Object?>{
      'event': 'terminalPulseChanged',
      'payload': <String, Object?>{
        'sessionId': 'session-1',
        'configuration': pulseConfiguration.toJson(),
        'armed': false,
        'error': 'Terminal Pulse watcher stopped: unavailable',
      },
    });
    final outputResyncEvent = _sendOutputResyncEvent(client, server);

    expect(launcher.starts, 1);
    expect(
      launcher.configs.single.toJson(),
      TerminalHostConfig.defaults.toJson(),
    );
    expect(attachment.sessionId, 'session-1');
    expect(attachment.created, isTrue);
    expect(attachment.running, isTrue);
    expect(attachment.snapshot, <int>[65, 66]);
    expect(restarted.created, isTrue);
    expect(resume.isDelta, isFalse);
    expect(resume.snapshot, <int>[83, 78, 65, 80]);
    expect(server.requestTypes, <String>[
      'hello',
      'createOrAttach',
      'terminal.restart',
      'write',
      'write',
      'resize',
      'terminal.pulse.status',
      'terminal.pulse.configure',
      'setOutputPaused',
      'detach',
      'terminate',
    ]);
    expect(server.payloadFor('hello')['clientKind'], 'app');
    expect(
      server.payloadFor('hello')['supportedTabKinds'],
      contains(aleraMobileEmulatorTabKind),
    );
    final createPayload = server.payloadFor('createOrAttach');
    expect(createPayload['workingDirectory'], '/repo');
    expect(createPayload['cols'], 80);
    expect(createPayload['rows'], 24);
    expect(
      createPayload['launch'],
      isNot(containsPair('setupCommand', anything)),
    );
    expect(server.payloadFor('terminal.restart')['sessionId'], 'session-1');
    final writePayloads = server.payloadsFor('write');
    expect(writePayloads, hasLength(2));
    expect(
      writePayloads[0]['dataBase64'],
      encodeTerminalHostBytes(<int>[1, 2]),
    );
    expect(writePayloads[0].containsKey('deferredEnter'), isFalse);
    expect(writePayloads[1]['dataBase64'], encodeTerminalHostBytes(<int>[3]));
    expect(writePayloads[1]['deferredEnter'], isTrue);
    expect(pulseStatus.configuration, const TerminalPulseConfiguration());
    expect(pulseStatus.armed, isFalse);
    expect(pulseStatus.statusKnown, isTrue);
    expect(configuredPulse.configuration, pulseConfiguration);
    expect(configuredPulse.armed, isTrue);
    expect(server.payloadFor('terminal.pulse.configure'), <String, Object?>{
      'sessionId': 'session-1',
      'configuration': pulseConfiguration.toJson(),
      'armed': true,
    });
    expect(server.payloadFor('setOutputPaused'), <String, Object?>{
      'sessionId': 'session-1',
      'paused': false,
    });
    expect((await outputEvent).data, <int>[65]);
    expect((await exitEvent).exitCode, 7);
    expect((await errorEvent).error, 'boom');
    final pulseChanged = (await pulseChangedEvent).state;
    expect(pulseChanged.configuration, pulseConfiguration);
    expect(pulseChanged.armed, isFalse);
    expect(pulseChanged.statusKnown, isTrue);
    expect(pulseChanged.error, 'Terminal Pulse watcher stopped: unavailable');
    expect((await outputResyncEvent).sessionId, 'session-1');

    client.dispose();
    client.dispose();
  });

  test('ensureStarted launches the host and sends initial config', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-warmup-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    final connectedEvent = client.runtimeEvents.first;
    const config = TerminalHostConfig(
      emptyShutdownDelaySeconds: 5,
      detachedSessionShutdownDelaySeconds: 10,
      scrollbackBytes: 1024,
    );

    await client.ensureStarted(config: config);

    expect(launcher.starts, 1);
    expect(launcher.configs.single.toJson(), config.toJson());
    expect(server.requestTypes, <String>['hello', 'configure']);
    expect(server.payloadFor('configure'), config.toJson());
    expect((await connectedEvent).name, aleraRuntimeHostConnectedEvent);
  });

  test(
    'shares an in-flight launch when terminal warmup starts first',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-terminal-runtime-race-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      final publishGate = Completer<void>();
      final launcher = _FakeTerminalHostLauncher(
        server: server,
        beforePublish: publishGate.future,
      );
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      final warmup = client.ensureStarted(config: TerminalHostConfig.defaults);
      await _waitForLauncherStart(launcher);
      final runtimeRequest = client.runtimeRequest('project.list');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(launcher.starts, 1);

      publishGate.complete();
      await Future.wait(<Future<Object?>>[warmup, runtimeRequest]);

      expect(launcher.starts, 1);
      expect(
        server.requestTypes,
        containsAll(<String>['hello', 'configure', 'project.list']),
      );
    },
  );

  test('shares an in-flight launch when runtime access starts first', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-runtime-terminal-race-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final publishGate = Completer<void>();
    final launcher = _FakeTerminalHostLauncher(
      server: server,
      beforePublish: publishGate.future,
    );
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    final runtimeRequest = client.runtimeRequest('project.list');
    await _waitForLauncherStart(launcher);
    final warmup = client.ensureStarted(config: TerminalHostConfig.defaults);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(launcher.starts, 1);

    publishGate.complete();
    await Future.wait(<Future<Object?>>[runtimeRequest, warmup]);

    expect(launcher.starts, 1);
    expect(
      server.requestTypes,
      containsAll(<String>['hello', 'project.list', 'configure']),
    );
  });

  test('only forwards runtime change events to runtimeEvents', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-runtime-events-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final client = SocketTerminalHostClient(
      launcher: _FakeTerminalHostLauncher(server: server),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.ensureStarted(config: TerminalHostConfig.defaults);
    final outputEvent = client.events
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    final runtimeEvent = client.runtimeEvents.first;

    server.send(<String, Object?>{
      'event': 'output',
      'payload': <String, Object?>{
        'sessionId': 'session-1',
        'dataBase64': encodeTerminalHostBytes(<int>[65]),
      },
    });
    server.send(<String, Object?>{
      'event': 'projectsChanged',
      'payload': <String, Object?>{'projectId': 'project-1'},
    });

    expect((await outputEvent).data, <int>[65]);
    final event = await runtimeEvent;
    expect(event.name, 'projectsChanged');
    expect(event.payload, <String, Object?>{'projectId': 'project-1'});
  });

  test(
    'configure updates connected hosts but does not start idle ones',
    () async {
      final idleTempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-config-idle-',
      );
      final activeTempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-config-active-',
      );
      addTearDown(() async {
        if (await idleTempDir.exists()) {
          await idleTempDir.delete(recursive: true);
        }
        if (await activeTempDir.exists()) {
          await activeTempDir.delete(recursive: true);
        }
      });
      final idleLauncher = _NoopTerminalHostLauncher();
      final idleClient = SocketTerminalHostClient(
        launcher: idleLauncher,
        applicationSupportDirectory: () async => idleTempDir,
      );
      addTearDown(idleClient.dispose);
      const config = TerminalHostConfig(
        emptyShutdownDelaySeconds: 6,
        detachedSessionShutdownDelaySeconds: 12,
        scrollbackBytes: 2048,
      );

      await idleClient.configure(config);

      expect(idleLauncher.starts, 0);

      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: activeTempDir,
        port: server.port,
        token: 'existing-token',
      );
      final activeClient = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => activeTempDir,
      );
      addTearDown(activeClient.dispose);

      await activeClient.ensureStarted(config: TerminalHostConfig.defaults);
      await activeClient.configure(config);

      expect(server.requestTypes, <String>['hello', 'configure', 'configure']);
      expect(server.payloadFor('configure'), config.toJson());
    },
  );

  test('reuses an existing control file and surfaces host errors', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-existing-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(errorForType: 'resize');
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.write(sessionId: 'session-1', bytes: const <int>[1]);
    await expectLater(
      client.resize(sessionId: 'session-1', cols: 100, rows: 30),
      throwsA(isA<StateError>()),
    );

    expect(launcher.starts, 0);
    expect(server.requestTypes.take(2), <String>['hello', 'write']);
  });

  test('fails pending requests when the host closes the socket', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-closes-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(closeForType: 'write');
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await expectLater(
      client.write(sessionId: 'session-1', bytes: const <int>[1]),
      throwsA(
        isA<TerminalHostConnectionClosedException>().having(
          (error) => error.toString(),
          'message',
          contains('connection closed'),
        ),
      ),
    );
  });

  test(
    'deletes stale controls and times out when launch does not publish one',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-stale-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await _writeControlFile(tempDir: tempDir, port: 1, token: 'stale-token');
      final client = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => tempDir,
        startupTimeout: Duration.zero,
      );
      addTearDown(client.dispose);

      Object? startupError;
      try {
        await client.detach('session-1');
        fail('expected startup to time out');
      } catch (error) {
        startupError = error;
      }

      expect(startupError, isA<TerminalHostStartupException>());
      final typedStartupError = startupError as TerminalHostStartupException;
      expect(typedStartupError.cause, isNull);
      expect(
        typedStartupError.toString(),
        'Terminal host did not start in time.',
      );
      expect(
        TerminalHostStartupException(SocketException('refused')).toString(),
        typedStartupError.toString(),
      );
      expect(
        TerminalHostStartupException(
          TimeoutException('authentication timed out'),
        ).toString(),
        typedStartupError.toString(),
      );

      final controlFile = File(
        p.join(tempDir.path, 'terminal_host', 'host.json'),
      );
      expect(await controlFile.exists(), isFalse);
    },
  );

  test('deletes stale legacy controls without runtime capability', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-legacy-control-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await _writeControlFile(
      tempDir: tempDir,
      port: 1,
      token: 'legacy-token',
      includeRuntimeCapability: false,
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
      startupTimeout: Duration.zero,
    );
    addTearDown(client.dispose);

    await expectLater(
      client.detach('session-1'),
      throwsA(isA<TerminalHostStartupException>()),
    );

    expect(
      await File(p.join(tempDir.path, 'terminal_host', 'host.json')).exists(),
      isFalse,
    );
  });

  test('records the cause of a failed terminal host startup', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-startup-cause-',
    );
    final logDir = await Directory.systemTemp.createTemp(
      'alera-host-client-startup-log-',
    );
    addTearDown(() async {
      await AppLogger.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (await logDir.exists()) {
        await logDir.delete(recursive: true);
      }
    });
    await AppLogger.resetForTesting();
    await AppLogger.configure(directory: logDir);
    final client = SocketTerminalHostClient(
      launcher: _FailingStartupTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
      startupTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(client.dispose);

    Object? startupError;
    try {
      await client.detach('session-1');
      fail('expected startup to time out');
    } catch (error) {
      startupError = error;
    }

    expect(startupError, isA<TerminalHostStartupException>());
    final typedStartupError = startupError as TerminalHostStartupException;
    expect(typedStartupError.cause, isA<SocketException>());
    await AppLogger.flush();
    final log = AppLogger.sink!.fileFor(0).readAsLinesSync().join('\n');
    expect(log, contains(typedStartupError.cause.toString()));
  });

  test('reuses a live legacy control for terminal requests', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-legacy-terminal-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'legacy-token',
      includeRuntimeCapability: false,
    );
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.ensureStarted(config: TerminalHostConfig.defaults);

    expect(launcher.starts, 0);
    expect(server.requestTypes, <String>['hello', 'configure']);
    expect(
      await File(p.join(tempDir.path, 'terminal_host', 'host.json')).exists(),
      isTrue,
    );
  });

  test(
    'starts a separate runtime host when terminal control is live legacy',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-legacy-runtime-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final legacyServer = await _TerminalHostTestServer.start();
      addTearDown(legacyServer.dispose);
      final runtimeServer = await _TerminalHostTestServer.start();
      addTearDown(runtimeServer.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: legacyServer.port,
        token: 'legacy-token',
        includeRuntimeCapability: false,
      );
      final launcher = _FakeTerminalHostLauncher(server: runtimeServer);
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await client.detach('session-1');
      await client.runtimeRequest('project.list');

      expect(launcher.starts, 1);
      expect(
        launcher.controlFilePaths.single,
        p.join(tempDir.path, 'terminal_host', 'runtime-host.json'),
      );
      expect(legacyServer.requestTypes, <String>['hello', 'detach']);
      expect(runtimeServer.requestTypes, <String>['hello', 'project.list']);
      expect(
        await File(p.join(tempDir.path, 'terminal_host', 'host.json')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(tempDir.path, 'terminal_host', 'runtime-host.json'))
            .exists(),
        isTrue,
      );
    },
  );

  test(
    'starts a separate runtime host when bootstrap capability is missing',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-no-bootstrap-capability-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final legacyServer = await _TerminalHostTestServer.start();
      addTearDown(legacyServer.dispose);
      final runtimeServer = await _TerminalHostTestServer.start();
      addTearDown(runtimeServer.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: legacyServer.port,
        token: 'legacy-token',
        includeRuntimeCapability: true,
        includeBootstrapCapability: false,
      );
      final launcher = _FakeTerminalHostLauncher(server: runtimeServer);
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await client.runtimeRequest('sshTarget.bootstrap.plan');

      expect(launcher.starts, 1);
      expect(legacyServer.requestTypes, isEmpty);
      expect(runtimeServer.requestTypes, <String>[
        'hello',
        'sshTarget.bootstrap.plan',
      ]);
    },
  );

  test('starts a separate runtime host when managed workspace capability is missing', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-no-managed-capability-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final legacyServer = await _TerminalHostTestServer.start();
    addTearDown(legacyServer.dispose);
    final runtimeServer = await _TerminalHostTestServer.start();
    addTearDown(runtimeServer.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: legacyServer.port,
      token: 'legacy-token',
      includeRuntimeCapability: true,
      includeBootstrapCapability: true,
      includeManagedWorkspaceCapability: false,
    );
    final launcher = _FakeTerminalHostLauncher(server: runtimeServer);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.runtimeRequest('workspace.createManaged');

    expect(launcher.starts, 1);
    expect(legacyServer.requestTypes, isEmpty);
    expect(runtimeServer.requestTypes, <String>[
      'hello',
      'workspace.createManaged',
    ]);
  });

  test(
    'does not split orchestration from a live PTY host without capability',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-no-orchestration-capability-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final legacyServer = await _TerminalHostTestServer.start();
      addTearDown(legacyServer.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: legacyServer.port,
        token: 'legacy-token',
        includeRuntimeCapability: true,
        includeBootstrapCapability: true,
        includeManagedWorkspaceCapability: true,
        includeOrchestrationCapability: false,
      );
      final launcher = _NoopTerminalHostLauncher();
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.runtimeRequest('orchestration.agentStatus', <String, Object?>{
          'entries': const <Object?>[],
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Restart Alera'),
          ),
        ),
      );

      expect(launcher.starts, 0);
      expect(legacyServer.requestTypes, <String>['hello']);
    },
  );

  test('does not split orchestration from a live runtime control without capability', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-runtime-no-orchestration-capability-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final legacyServer = await _TerminalHostTestServer.start();
    addTearDown(legacyServer.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      fileName: 'runtime-host.json',
      port: legacyServer.port,
      token: 'legacy-token',
      includeRuntimeCapability: true,
      includeBootstrapCapability: true,
      includeManagedWorkspaceCapability: true,
      includeOrchestrationCapability: false,
    );
    final launcher = _NoopTerminalHostLauncher();
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await expectLater(
      client.runtimeRequest('orchestration.agentStatus', <String, Object?>{
        'entries': const <Object?>[],
      }),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Restart Alera'),
        ),
      ),
    );

    expect(launcher.starts, 0);
    expect(legacyServer.requestTypes, <String>['hello']);
  });

  test(
    'failed orchestration capability checks do not poison runtime requests',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-orchestration-failure-runtime-retry-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final legacyServer = await _TerminalHostTestServer.start();
      addTearDown(legacyServer.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: legacyServer.port,
        token: 'legacy-token',
        includeRuntimeCapability: true,
        includeBootstrapCapability: true,
        includeManagedWorkspaceCapability: true,
        includeOrchestrationCapability: false,
      );
      final launcher = _NoopTerminalHostLauncher();
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.runtimeRequest('orchestration.agentStatus', <String, Object?>{
          'entries': const <Object?>[],
        }),
        throwsA(isA<StateError>()),
      );
      await client.runtimeRequest('project.list');

      expect(launcher.starts, 0);
      expect(legacyServer.requestTypes, <String>[
        'hello',
        'hello',
        'project.list',
      ]);
    },
  );

  test('normal runtime requests ignore in-flight orchestration capability failures', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-inflight-orchestration-failure-runtime-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final releaseHello = Completer<void>();
    final legacyServer = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type == 'hello') {
          await releaseHello.future;
        }
      },
    );
    addTearDown(legacyServer.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: legacyServer.port,
      token: 'legacy-token',
      includeRuntimeCapability: true,
      includeBootstrapCapability: true,
      includeManagedWorkspaceCapability: true,
      includeOrchestrationCapability: false,
    );
    final launcher = _NoopTerminalHostLauncher();
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    final orchestrationRequest = client.runtimeRequest(
      'orchestration.agentStatus',
      <String, Object?>{'entries': const <Object?>[]},
    );
    await _waitForServerRequestCount(legacyServer, 1);
    final runtimeRequest = client.runtimeRequest('project.list');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    releaseHello.complete();
    await expectLater(orchestrationRequest, throwsA(isA<StateError>()));
    await runtimeRequest;

    expect(launcher.starts, 0);
    expect(legacyServer.requestTypes, <String>[
      'hello',
      'hello',
      'project.list',
    ]);
  });

  test(
    'does not split orchestration from an in-flight host without capability',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-inflight-no-orchestration-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final legacyServer = await _TerminalHostTestServer.start();
      addTearDown(legacyServer.dispose);
      final runtimeServer = await _TerminalHostTestServer.start();
      addTearDown(runtimeServer.dispose);
      final releaseFirstLaunch = Completer<void>();
      final launcher = _QueuedTerminalHostLauncher(<_QueuedTerminalHostLaunch>[
        _QueuedTerminalHostLaunch(
          server: legacyServer,
          beforePublish: releaseFirstLaunch.future,
          includeOrchestrationCapability: false,
        ),
        _QueuedTerminalHostLaunch(server: runtimeServer),
      ]);
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      final firstRequest = client.runtimeRequest('project.list');
      await _waitForQueuedLauncherStarts(launcher, 1);
      final orchestrationRequest = client.runtimeRequest(
        'orchestration.agentStatus',
        <String, Object?>{'entries': const <Object?>[]},
      );
      releaseFirstLaunch.complete();

      await firstRequest;
      await expectLater(
        orchestrationRequest,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Restart Alera'),
          ),
        ),
      );

      expect(launcher.starts, 1);
      expect(legacyServer.requestTypes, <String>[
        'hello',
        'project.list',
        'hello',
      ]);
      expect(runtimeServer.requestTypes, isEmpty);
    },
  );

  test(
    'reuses a runtime control for terminal requests when no legacy exists',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-runtime-first-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      final launcher = _FakeTerminalHostLauncher(server: server);
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await client.runtimeRequest('project.list');
      await client.detach('session-1');

      expect(launcher.starts, 1);
      expect(server.requestTypes, <String>['hello', 'project.list', 'detach']);
    },
  );

  test('rejects requests after disposal', () async {
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => Directory.systemTemp,
    );

    client.dispose();

    await expectLater(
      client.write(sessionId: 'session-1', bytes: const <int>[1]),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      client.configure(TerminalHostConfig.defaults),
      throwsA(isA<StateError>()),
    );
  });
}

GhosttyTerminalShellLaunch _launch({String? setupCommand}) {
  return GhosttyTerminalShellLaunch(
    label: 'shell',
    shell: '/bin/sh',
    arguments: const <String>['-l'],
    environment: const <String, String>{'TERM': 'xterm-256color'},
    setupCommand: setupCommand,
  );
}

Future<void> _waitForLauncherStart(_FakeTerminalHostLauncher launcher) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (launcher.starts == 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(launcher.starts, greaterThan(0));
}

Future<void> _waitForQueuedLauncherStarts(
  _QueuedTerminalHostLauncher launcher,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (launcher.starts < expected && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(launcher.starts, greaterThanOrEqualTo(expected));
}

Future<void> _writeControlFile({
  required Directory tempDir,
  String fileName = 'host.json',
  required int port,
  required String token,
  int protocolVersion = aleraTerminalHostProtocolVersion,
  bool includeRuntimeCapability = true,
  bool includeBootstrapCapability = true,
  bool includeManagedWorkspaceCapability = true,
  bool includeOrchestrationCapability = true,
  bool includeBinaryFramesCapability = false,
}) async {
  final runtimeDir = Directory(p.join(tempDir.path, 'terminal_host'));
  await runtimeDir.create(recursive: true);
  final payload = <String, Object?>{
    'protocolVersion': protocolVersion,
    'port': port,
    'token': token,
  };
  final capabilities = <String>[
    if (includeRuntimeCapability) ...<String>[
      aleraRuntimeHostCapability,
      if (includeBootstrapCapability) aleraRuntimeHostBootstrapCapability,
      if (includeManagedWorkspaceCapability)
        aleraRuntimeHostManagedWorkspaceCapability,
      if (includeOrchestrationCapability)
        aleraRuntimeHostOrchestrationCapability,
      if (includeBinaryFramesCapability) aleraRuntimeHostBinaryFramesCapability,
    ],
  ];
  if (capabilities.isNotEmpty) {
    payload['runtimeCapabilities'] = capabilities;
  }
  await File(p.join(runtimeDir.path, fileName))
      .writeAsString(jsonEncode(payload));
}

final class _QueuedTerminalHostLaunch {
  const _QueuedTerminalHostLaunch({
    required this.server,
    this.beforePublish,
    this.includeOrchestrationCapability = true,
  });

  final _TerminalHostTestServer server;
  final Future<void>? beforePublish;
  final bool includeOrchestrationCapability;
}

final class _QueuedTerminalHostLauncher implements TerminalHostProcessLauncher {
  _QueuedTerminalHostLauncher(this._launches);

  final List<_QueuedTerminalHostLaunch> _launches;
  int starts = 0;

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    final launch = _launches[starts];
    starts += 1;
    launch.server.token = token;
    await launch.beforePublish;
    await File(controlFilePath).parent.create(recursive: true);
    await File(controlFilePath).writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'port': launch.server.port,
        'token': token,
        'runtimeCapabilities': <String>[
          aleraRuntimeHostCapability,
          aleraRuntimeHostBootstrapCapability,
          aleraRuntimeHostManagedWorkspaceCapability,
          if (launch.includeOrchestrationCapability)
            aleraRuntimeHostOrchestrationCapability,
        ],
      }),
    );
  }
}

final class _NoopTerminalHostLauncher implements TerminalHostProcessLauncher {
  int starts = 0;

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    starts += 1;
  }
}

final class _FailingStartupTerminalHostLauncher
    implements TerminalHostProcessLauncher {
  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    final controlFile = File(controlFilePath);
    await controlFile.parent.create(recursive: true);
    await controlFile.writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'port': 1,
        'token': token,
        'runtimeCapabilities': <String>[
          aleraRuntimeHostCapability,
          aleraRuntimeHostBootstrapCapability,
          aleraRuntimeHostManagedWorkspaceCapability,
          aleraRuntimeHostOrchestrationCapability,
        ],
      }),
    );
  }
}
