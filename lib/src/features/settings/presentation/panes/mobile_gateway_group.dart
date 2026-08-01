import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_access_status.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_endpoint_rules.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Mode shown by the selector. Pre-existing custom bind hosts persisted before
/// endpoint modes existed report loopback, so a non-loopback bind renders as
/// Manual instead of misrepresenting the effective configuration.
MobileEndpointMode displayedEndpointMode(MobileGatewaySettings settings) {
  if (settings.endpointMode == MobileEndpointMode.loopback &&
      !isLoopbackEndpointHost(settings.bindHost)) {
    return MobileEndpointMode.manual;
  }
  return settings.endpointMode;
}

/// Gateway settings group with the connection-mode selector. Presentational:
/// state and runtime calls stay in the mobile devices pane.
class MobileGatewayGroup extends StatelessWidget {
  const MobileGatewayGroup({
    super.key,
    required this.status,
    required this.bindHostController,
    required this.gatewayPort,
    required this.applying,
    required this.onEnabledChanged,
    required this.onModeSelected,
    required this.onBindHostChanged,
    required this.onPortChanged,
    required this.onApply,
  });

  final MobileAccessStatus status;
  final TextEditingController bindHostController;
  final int gatewayPort;
  final bool applying;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<MobileEndpointMode> onModeSelected;
  final ValueChanged<String> onBindHostChanged;
  final ValueChanged<int> onPortChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final settings = status.settings;
    final mode = displayedEndpointMode(settings);
    return AleraSettingsGroup(
      title: 'Mobile Gateway',
      description:
          'WebSocket listener the mobile companion app connects to. '
          'Applying changes restarts the gateway and disconnects '
          'connected devices.',
      children: <Widget>[
        SettingsSwitchRow(
          title: 'Enable Mobile Access',
          description: 'Accept connections from paired mobile devices.',
          value: settings.enabled,
          onChanged: applying ? (_) {} : onEnabledChanged,
        ),
        AleraSettingRow(
          title: 'Connection Mode',
          description: switch (mode) {
            MobileEndpointMode.loopback =>
              'Only this machine can reach the gateway.',
            MobileEndpointMode.tailscale =>
              'Devices on your Tailnet reach the gateway over Tailscale.',
            MobileEndpointMode.manual =>
              'Configure the bind host and endpoint yourself.',
          },
          controlWidth: 320,
          child: Align(
            alignment: Alignment.centerRight,
            child: AleraSegmentedButton<MobileEndpointMode>(
              dense: true,
              segments: const <ButtonSegment<MobileEndpointMode>>[
                ButtonSegment<MobileEndpointMode>(
                  value: MobileEndpointMode.loopback,
                  label: Text('This Device'),
                ),
                ButtonSegment<MobileEndpointMode>(
                  value: MobileEndpointMode.tailscale,
                  label: Text('Tailscale'),
                ),
                ButtonSegment<MobileEndpointMode>(
                  value: MobileEndpointMode.manual,
                  label: Text('Manual'),
                ),
              ],
              selected: mode,
              onSelectionChanged: applying ? (_) {} : onModeSelected,
            ),
          ),
        ),
        if (mode == MobileEndpointMode.tailscale) ...<Widget>[
          _tailscaleStatusRow(),
          if (defaultTargetPlatform == TargetPlatform.windows)
            const AleraSettingRow(
              title: 'Windows Firewall',
              description:
                  'If the phone cannot connect, allow Alera through Windows '
                  'Firewall for incoming connections on the gateway port.',
              child: SizedBox.shrink(),
            ),
        ],
        if (mode == MobileEndpointMode.manual) ...<Widget>[
          AleraSettingRow(
            title: 'Bind Host',
            description: 'Interface the gateway listens on.',
            child: AleraTextField(
              controller: bindHostController,
              hintText: '127.0.0.1',
              onChanged: onBindHostChanged,
            ),
          ),
          if (_bindHostHint() case final String hint)
            AleraSettingRow(
              title: 'Network Hint',
              description: hint,
              child: const SizedBox.shrink(),
            ),
        ],
        SettingsIntegerRow(
          title: 'Port',
          description: 'Gateway listener port.',
          value: gatewayPort,
          min: 1,
          max: 65535,
          step: 1,
          onChanged: onPortChanged,
        ),
        AleraSettingRow(
          title: 'Apply Gateway Settings',
          description: 'Persist gateway changes.',
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: applying ? null : onApply,
              child: Text(applying ? 'Applying…' : 'Apply'),
            ),
          ),
        ),
      ],
    );
  }

  String? _bindHostHint() {
    return mobileGatewayBindHostHint(
      bindHost: bindHostController.text,
      port: gatewayPort,
    );
  }

  Widget _tailscaleStatusRow() {
    final tailscale = status.tailscale;
    final (bool active, String label, String description) = switch (tailscale) {
      null => (
        false,
        'Unknown',
        'The runtime does not report Tailscale - update the Alera CLI.',
      ),
      MobileTailscaleStatus(detected: false) => (
        false,
        'Not detected',
        'Install Tailscale on this machine to use this mode.',
      ),
      MobileTailscaleStatus(running: false) => (
        false,
        'Not running',
        tailscale.error ?? 'Run "tailscale up" and sign in to your Tailnet.',
      ),
      MobileTailscaleStatus(tailnetIp: final String ip) => (
        true,
        'Running · $ip',
        'Devices signed in to the same Tailnet can pair and connect.',
      ),
      _ => (
        false,
        'No Tailnet IP',
        'Tailscale is running but reported no Tailnet IPv4 address.',
      ),
    };
    return AleraSettingRow(
      title: 'Tailscale Status',
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AleraStatusDot(active: active),
            const SizedBox(width: AleraTokens.space6),
            Flexible(child: AleraBadge(label: label)),
          ],
        ),
      ),
    );
  }
}
