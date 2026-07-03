import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Scaffold', group: 'Master detail', size: Size(640, 320))
Widget aleraMasterDetailPreview() => SizedBox(
  width: 600,
  height: 280,
  child: AleraMasterDetail(
    masterTitle: 'Remote Hosts',
    masterAction: const AleraIconButton(
      icon: AleraIcons.add,
      tooltip: 'New Host',
      onPressed: _noop,
    ),
    master: AleraPanel(
      children: <Widget>[
        AleraMenuItem(label: 'build-server', selected: true, onTap: _noop),
        AleraMenuItem(label: 'staging', selected: false, onTap: _noop),
        AleraMenuItem(label: 'gpu-box', selected: false, onTap: _noop),
      ],
    ),
    detail: const AleraEmptyState(
      title: 'Select A Host',
      message: 'Pick a host from the list to edit its connection.',
      icon: AleraIcons.host,
    ),
  ),
);

void _noop() {}
