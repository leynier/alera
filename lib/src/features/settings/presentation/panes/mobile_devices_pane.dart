import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/mobile_devices/application/mobile_access_providers.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_access_status.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_endpoint_rules.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_device_list_row.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_device_rename_dialog.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_gateway_group.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_pairing_dialog.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_pairing_offer_row.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileDevicesSettingsPane extends ConsumerStatefulWidget {
  const MobileDevicesSettingsPane({
    super.key,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final Map<String, GlobalKey> groupKeys;

  @override
  ConsumerState<MobileDevicesSettingsPane> createState() =>
      _MobileDevicesSettingsPaneState();
}

class _MobileDevicesSettingsPaneState
    extends ConsumerState<MobileDevicesSettingsPane> {
  final TextEditingController _bindHostController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  int _gatewayPort = 6768;
  int _expiresMinutes = 10;
  String? _gatewaySignature;
  String? _error;
  bool _applying = false;
  bool _generating = false;

  @override
  void dispose() {
    _bindHostController.dispose();
    _endpointController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  void _seedFromSettings(MobileGatewaySettings settings) {
    final signature =
        '${settings.enabled}|${settings.bindHost}|${settings.port}|'
        '${settings.endpointMode.name}';
    if (_gatewaySignature == signature) {
      return;
    }
    _bindHostController.text = settings.bindHost;
    _gatewayPort = settings.port;
    _gatewaySignature = signature;
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(mobileAccessStatusProvider);
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AleraEmptyState(
        icon: AleraIcons.mobileDevice,
        title: 'Mobile Access Unavailable',
        message: error.toString(),
      ),
      data: (status) {
        _seedFromSettings(status.settings);
        // Resource sections own their scroll context (see SettingsContent),
        // so this flat pane scrolls itself.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KeyedSubtree(
                key: widget.groupKeys['gateway'],
                child: _gatewayGroup(status),
              ),
              const SizedBox(height: AleraTokens.space16),
              KeyedSubtree(
                key: widget.groupKeys['pairing'],
                child: _pairingGroup(status),
              ),
              const SizedBox(height: AleraTokens.space16),
              KeyedSubtree(
                key: widget.groupKeys['offers'],
                child: _offersGroup(status),
              ),
              const SizedBox(height: AleraTokens.space16),
              KeyedSubtree(
                key: widget.groupKeys['devices'],
                child: _devicesGroup(status),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _gatewayGroup(MobileAccessStatus status) {
    return MobileGatewayGroup(
      status: status,
      bindHostController: _bindHostController,
      gatewayPort: _gatewayPort,
      applying: _applying,
      onEnabledChanged: (enabled) => _applySettings(enabled: enabled),
      onModeSelected: _selectMode,
      onBindHostChanged: (_) => setState(() {}),
      onPortChanged: (value) => setState(() => _gatewayPort = value),
      onApply: _applySettings,
    );
  }

  Widget _pairingGroup(MobileAccessStatus status) {
    final tailscaleMode =
        displayedEndpointMode(status.settings) == MobileEndpointMode.tailscale;
    return AleraSettingsGroup(
      title: 'Link A Device',
      description:
          'Generates a one-time QR offer for the Alera mobile app. The QR is '
          'only shown at creation time.',
      children: <Widget>[
        if (!tailscaleMode)
          AleraSettingRow(
            title: 'Endpoint',
            description:
                'Optional wss://host:port the phone connects to. Leave empty '
                'to use the bind host.',
            child: AleraTextField(
              controller: _endpointController,
              hintText: 'wss://host-or-vpn-name:${status.settings.port}',
              onChanged: (_) => setState(() {}),
            ),
          ),
        AleraSettingRow(
          title: 'Device Name',
          description: 'Optional expected name for the new device.',
          child: AleraTextField(
            controller: _deviceNameController,
            hintText: 'My Phone',
          ),
        ),
        SettingsIntegerRow(
          title: 'Expires In',
          description: 'Minutes before the offer expires.',
          value: _expiresMinutes,
          min: 1,
          max: 60,
          step: 1,
          suffix: 'min',
          onChanged: (value) => setState(() => _expiresMinutes = value),
        ),
        AleraSettingRow(
          title: 'Generate Pairing QR',
          description: 'Enables the gateway if it is disabled.',
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _generating ? null : () => _generateOffer(status),
              icon: const Icon(AleraIcons.qrCode, size: 16),
              label: Text(_generating ? 'Generating…' : 'Generate'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _offersGroup(MobileAccessStatus status) {
    return AleraSettingsGroup(
      title: 'Active Pairing Offers',
      description:
          'Pending offers waiting to be claimed. The QR for an existing offer '
          'cannot be shown again - cancel it and generate a new one.',
      children: <Widget>[
        if (status.activePairings.isEmpty)
          const AleraEmptyState(
            icon: AleraIcons.qrCode,
            title: 'No Active Offers',
            message: 'Generate A Pairing QR To Link A New Device.',
          )
        else
          AleraPanel(
            clipBehavior: Clip.antiAlias,
            children: <Widget>[
              for (final offer in status.activePairings)
                MobilePairingOfferRow(
                  offer: offer,
                  onCancel: () => _cancelOffer(offer.id),
                ),
            ],
          ),
      ],
    );
  }

  Widget _devicesGroup(MobileAccessStatus status) {
    return AleraSettingsGroup(
      title: 'Paired Devices',
      description: 'Devices that can connect to this runtime.',
      children: <Widget>[
        if (status.devices.isEmpty)
          const AleraEmptyState(
            icon: AleraIcons.mobileDevice,
            title: 'No Paired Devices',
            message: 'Link A Device To See It Here.',
          )
        else
          AleraPanel(
            clipBehavior: Clip.antiAlias,
            children: <Widget>[
              for (final device in status.devices)
                MobileDeviceListRow(
                  device: device,
                  onRename: () => _renameDevice(device),
                  onRevoke: () => _revokeDevice(device),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _applySettings({bool? enabled}) async {
    final bindHost = _bindHostController.text.trim();
    await _updateSettings(
      enabled: enabled,
      bindHost: bindHost.isEmpty ? null : bindHost,
      port: _gatewayPort,
    );
  }

  Future<void> _selectMode(MobileEndpointMode mode) async {
    // Only the mode is sent: the runtime resolves the tailnet bind host or
    // resets loopback itself, so a stale local bind host must not ride along.
    await _updateSettings(endpointMode: mode);
  }

  Future<void> _updateSettings({
    bool? enabled,
    String? bindHost,
    int? port,
    MobileEndpointMode? endpointMode,
  }) async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref
          .read(mobileAccessRepositoryProvider)
          .updateSettings(
            enabled: enabled,
            bindHost: bindHost,
            port: port,
            endpointMode: endpointMode,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _applying = false;
        _gatewaySignature = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _applying = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _generateOffer(MobileAccessStatus status) async {
    final endpoint = _endpointController.text.trim();
    if (endpoint.isNotEmpty) {
      final validationError = validateMobilePairingEndpoint(
        endpoint: endpoint,
        gatewayEnabled: status.settings.enabled,
        gatewayPort: status.settings.port,
      );
      if (validationError != null) {
        setState(() => _error = validationError);
        return;
      }
    } else if (isWildcardBindHost(status.settings.bindHost)) {
      setState(() {
        _error =
            'Wildcard Bind Hosts Require An Explicit wss:// Endpoint To '
            'Create An Offer';
      });
      return;
    }
    final deviceName = _deviceNameController.text.trim();
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final grant = await ref
          .read(mobileAccessRepositoryProvider)
          .createPairingOffer(
            endpoint: endpoint.isEmpty ? null : endpoint,
            deviceName: deviceName.isEmpty ? null : deviceName,
            expiresMinutes: _expiresMinutes,
          );
      if (!mounted) {
        return;
      }
      setState(() => _generating = false);
      await showDialog<void>(
        context: context,
        builder: (_) => MobilePairingDialog(
          grant: grant,
          onCancelOffer: () => ref
              .read(mobileAccessRepositoryProvider)
              .cancelPairingOffer(grant.pairingId),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generating = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _cancelOffer(String offerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Cancel Pairing Offer',
        message: 'The offer becomes unusable immediately.',
        confirmLabel: 'Cancel Offer',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(mobileAccessRepositoryProvider)
          .cancelPairingOffer(offerId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _renameDevice(MobileDevice device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => MobileDeviceRenameDialog(initialName: device.displayName),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == device.displayName || !mounted) {
      return;
    }
    try {
      await ref
          .read(mobileAccessRepositoryProvider)
          .renameDevice(id: device.id, displayName: trimmed);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _revokeDevice(MobileDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Revoke ${device.displayName}',
        message:
            'The device loses access and active sessions disconnect '
            'immediately. This cannot be undone.',
        confirmLabel: 'Revoke',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(mobileAccessRepositoryProvider).revokeDevice(device.id);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }
}
