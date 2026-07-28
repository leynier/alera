import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_providers.dart';
import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_device_picker.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device picker returns an available Android virtual device', (
    tester,
  ) async {
    final client = _PickerRuntimeHostClient();
    final service = MobileEmulatorService(client);
    addTearDown(service.dispose);
    MobileEmulatorDevice? selected;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mobileEmulatorServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showMobileEmulatorDevicePicker(context);
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(find.text('Open Mobile Emulator'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('API 35 - stopped'), findsOneWidget);

    await tester.tap(find.text('Pixel 9'));
    await tester.pumpAndSettle();

    expect(selected?.id, 'pixel-9');
    expect(client.devicePlatform, 'android');
  });
}

final class _PickerRuntimeHostClient implements RuntimeHostClient {
  String? devicePlatform;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    return switch (type) {
      'status.get' => <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostMobileEmulatorCapability,
        ],
      },
      'emulator.capabilities' => <String, Object?>{
        'ok': true,
        'platforms': <String, Object?>{
          'android': <String, Object?>{'available': true, 'message': 'Ready'},
          'ios': <String, Object?>{
            'available': false,
            'message': 'iOS Requires Apple Silicon.',
          },
        },
      },
      'emulator.devices' => _devices(payload),
      _ => throw StateError('Unexpected runtime request: $type'),
    };
  }

  Map<String, Object?> _devices(Map<String, Object?> payload) {
    devicePlatform = payload['platform'] as String?;
    return <String, Object?>{
      'ok': true,
      'items': <Object?>[
        <String, Object?>{
          'id': 'pixel-9',
          'platform': 'android',
          'name': 'Pixel 9',
          'runtime': 'API 35',
          'state': 'stopped',
          'available': true,
        },
      ],
    };
  }
}
