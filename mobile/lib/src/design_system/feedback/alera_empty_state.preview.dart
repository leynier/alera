import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Empty State', group: 'Feedback')
Widget aleraEmptyStatePreview() => AleraEmptyState(
  icon: AleraIcons.pairedDevices,
  title: 'No paired hosts',
  message: 'Open Alera on your computer, go to Settings > Mobile Devices, generate a pairing QR code, and scan it with this phone.',
  action: FilledButton.icon(
    onPressed: () {},
    icon: const Icon(AleraIcons.qrCode),
    label: const Text('Pair Host'),
  ),
);

@AleraPreview(name: 'Error State', group: 'Feedback')
Widget aleraEmptyStateErrorPreview() => AleraEmptyState(
  icon: AleraIcons.cloudOff,
  title: 'Could not load hosts',
  message: 'Pull down or tap Retry to try again.',
  detail: 'SocketException: Connection refused (OS Error: errno = 111)',
  action: FilledButton.icon(
    onPressed: () {},
    icon: const Icon(AleraIcons.refresh),
    label: const Text('Retry'),
  ),
);
