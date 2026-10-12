import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/lists/alera_key_value_list.dart';
import 'package:flutter/material.dart';

const List<AleraKeyValue> _entries = <AleraKeyValue>[
  AleraKeyValue(label: 'Workflow', value: 'feature-delivery'),
  AleraKeyValue(
    label: 'Run Id',
    value: 'run_01J9ZK4Q7M2V8S3T',
    mono: true,
    copyable: true,
  ),
  AleraKeyValue(label: 'Started', value: 'Today at 13:42'),
];

@AleraPreview(name: 'Wide', group: 'Key value list', size: Size(480, 160))
Widget aleraKeyValueListPreview() => const AleraKeyValueList(entries: _entries);

@AleraPreview(name: 'Stacked', group: 'Key value list', size: Size(300, 240))
Widget aleraKeyValueListStackedPreview() =>
    const AleraKeyValueList(entries: _entries);
