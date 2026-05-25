import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Label', group: 'Section header', size: Size(260, 48))
Widget aleraSectionHeaderPreview() =>
    const AleraSectionHeader(label: 'Projects');

@AleraPreview(name: 'With icon', group: 'Section header', size: Size(260, 48))
Widget aleraSectionHeaderIconPreview() =>
    const AleraSectionHeader(label: 'Workspaces', leadingIcon: Icons.folder);
