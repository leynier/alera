import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:flutter/material.dart';

/// The one badge every remote host surface shows for a host's state.
class const RemoteHostStatusBadge({
  super.key,
  required final RemoteHostStatus status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraBadge(
      label: status.label,
      tone: remoteHostBadgeTone(status.tone),
      dot: status.showsDot,
    );
  }
}

AleraBadgeTone remoteHostBadgeTone(RemoteHostStatusTone tone) {
  return switch (tone) {
    RemoteHostStatusTone.neutral => AleraBadgeTone.neutral,
    RemoteHostStatusTone.attention => AleraBadgeTone.attention,
    RemoteHostStatusTone.info => AleraBadgeTone.info,
    RemoteHostStatusTone.success => AleraBadgeTone.success,
    RemoteHostStatusTone.error => AleraBadgeTone.error,
  };
}

/// Color of the header's status indicator, matching the badge tone.
Color remoteHostStatusColor(RemoteHostStatus status) {
  return switch (status.tone) {
    RemoteHostStatusTone.neutral => AleraTokens.foregroundMuted,
    RemoteHostStatusTone.attention => AleraTokens.warning,
    RemoteHostStatusTone.info => AleraTokens.info,
    RemoteHostStatusTone.success => AleraTokens.success,
    RemoteHostStatusTone.error => AleraTokens.error,
  };
}

/// Glyph of the header's status indicator.
IconData remoteHostStatusIcon(RemoteHostStatus status) {
  return switch (status) {
    RemoteHostNeedsSetup() => AleraIcons.download,
    RemoteHostInstalling() => AleraIcons.downloading,
    RemoteHostDisconnected() => AleraIcons.unlink,
    RemoteHostOffline() => AleraIcons.unlink,
    RemoteHostConnecting() => AleraIcons.sync,
    RemoteHostConnected(:final updateAvailable) =>
      updateAvailable ? AleraIcons.updateAvailable : AleraIcons.link,
    RemoteHostError() => AleraIcons.error,
  };
}
