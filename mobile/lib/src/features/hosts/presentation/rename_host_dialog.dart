import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showRenameHostDialog(
  BuildContext context,
  WidgetRef ref,
  PairedHostProfile host,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => AleraRenameDialog(
      title: 'Rename Host',
      labelText: 'Host Name',
      initialValue: host.alias ?? host.displayName,
      helperText: 'Leave empty to use the advertised host name',
      allowEmpty: true,
    ),
  );
  if (name == null) {
    return;
  }
  await ref
      .read(pairedHostsControllerProvider.notifier)
      .updateHostAlias(host.id, name);
}
