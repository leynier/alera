import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'All platforms', group: 'Host OS icon')
Widget aleraHostOsIconPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraHostOsIcon(os: HostOs.macos, size: AleraTokens.iconLg),
    SizedBox(width: AleraTokens.space12),
    AleraHostOsIcon(os: HostOs.windows, size: AleraTokens.iconLg),
    SizedBox(width: AleraTokens.space12),
    AleraHostOsIcon(os: HostOs.linux, size: AleraTokens.iconLg),
    SizedBox(width: AleraTokens.space12),
    AleraHostOsIcon(os: HostOs.unknown, size: AleraTokens.iconLg),
  ],
);

@AleraPreview(name: 'Sidebar size', group: 'Host OS icon')
Widget aleraHostOsIconSidebarPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraHostOsIcon(os: HostOs.macos),
    SizedBox(width: AleraTokens.space8),
    AleraHostOsIcon(os: HostOs.windows),
    SizedBox(width: AleraTokens.space8),
    AleraHostOsIcon(os: HostOs.linux),
  ],
);
