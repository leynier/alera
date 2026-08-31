import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/keep_alive/presentation/keep_alive_status_chip.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Keep Alive Off', group: 'Status Bar')
Widget keepAliveStatusChipOffPreview() => Material(
  child: KeepAliveStatusChip(
    snapshot: const .inactive(),
    enabled: false,
    onPressed: () {},
  ),
);

@AleraPreview(name: 'Keep Alive On', group: 'Status Bar')
Widget keepAliveStatusChipOnPreview() => Material(
  child: KeepAliveStatusChip(
    snapshot: const .active(),
    enabled: true,
    onPressed: () {},
  ),
);

@AleraPreview(name: 'Keep Alive Error', group: 'Status Bar')
Widget keepAliveStatusChipErrorPreview() => Material(
  child: KeepAliveStatusChip(
    snapshot: const .inactive(error: 'not supported'),
    enabled: false,
    onPressed: () {},
  ),
);
