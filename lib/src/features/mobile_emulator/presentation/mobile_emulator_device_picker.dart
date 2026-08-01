import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_providers.dart';
import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<MobileEmulatorDevice?> showMobileEmulatorDevicePicker(
  BuildContext context,
) {
  return showDialog<MobileEmulatorDevice>(
    context: context,
    builder: (_) => const MobileEmulatorDevicePicker(),
  );
}

class MobileEmulatorDevicePicker extends ConsumerStatefulWidget {
  const MobileEmulatorDevicePicker({super.key});

  @override
  ConsumerState<MobileEmulatorDevicePicker> createState() =>
      _MobileEmulatorDevicePickerState();
}

class _MobileEmulatorDevicePickerState
    extends ConsumerState<MobileEmulatorDevicePicker> {
  MobileEmulatorPlatform _platform = MobileEmulatorPlatform.android;
  late Future<_PickerData> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final service = ref.read(mobileEmulatorServiceProvider);
    _data = service.capabilities().then((capabilities) async {
      final available = MobileEmulatorPlatform.values.where(
        (platform) => capabilities[platform]?.available == true,
      );
      if (capabilities[_platform]?.available != true && available.isNotEmpty) {
        _platform = available.first;
      }
      final devices = capabilities[_platform]?.available == true
          ? await service.devices(platform: _platform)
          : const <MobileEmulatorDevice>[];
      return _PickerData(capabilities: capabilities, devices: devices);
    });
  }

  void _selectPlatform(MobileEmulatorPlatform platform) {
    if (platform == _platform) {
      return;
    }
    setState(() {
      _platform = platform;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: AleraTokens.imageMaxWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Open Mobile Emulator',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            SizedBox(
              height: AleraTokens.space48 * 5,
              child: FutureBuilder<_PickerData>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _PickerMessage(
                      message: 'Device discovery failed',
                      detail: snapshot.error.toString(),
                      onRetry: () => setState(_reload),
                    );
                  }
                  final data = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AleraSegmentedButton<MobileEmulatorPlatform>(
                        segments: <ButtonSegment<MobileEmulatorPlatform>>[
                          for (final platform in MobileEmulatorPlatform.values)
                            ButtonSegment<MobileEmulatorPlatform>(
                              value: platform,
                              enabled:
                                  data.capabilities[platform]?.available ==
                                  true,
                              label: Text(platform.label),
                            ),
                        ],
                        selected: _platform,
                        onSelectionChanged: _selectPlatform,
                      ),
                      const SizedBox(height: AleraTokens.space12),
                      Expanded(child: _buildDevices(context, data)),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevices(BuildContext context, _PickerData data) {
    if (data.devices.isEmpty) {
      final capability = data.capabilities[_platform];
      return _PickerMessage(
        message: capability?.available == false
            ? 'Platform unavailable'
            : 'No virtual devices found',
        detail: capability?.available == false
            ? capability!.message
            : _platform == MobileEmulatorPlatform.android
            ? 'Create an Android virtual device and retry.'
            : 'Install an iOS simulator runtime and retry.',
        onRetry: () => setState(_reload),
      );
    }
    return ListView.separated(
      itemCount: data.devices.length,
      separatorBuilder: (_, _) => const Divider(height: AleraTokens.space2),
      itemBuilder: (context, index) {
        final device = data.devices[index];
        return ListTile(
          enabled: device.available,
          title: Text(device.name),
          subtitle: Text(<String>[?device.runtime, device.state].join(' - ')),
          onTap: () => Navigator.of(context).pop(device),
        );
      },
    );
  }
}

class _PickerData {
  const _PickerData({required this.capabilities, required this.devices});

  final Map<MobileEmulatorPlatform, MobileEmulatorCapability> capabilities;
  final List<MobileEmulatorDevice> devices;
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      title: message,
      message: detail,
      action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}
