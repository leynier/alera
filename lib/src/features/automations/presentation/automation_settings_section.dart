import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AutomationSettingsSection extends ConsumerStatefulWidget {
  const AutomationSettingsSection({super.key});

  @override
  ConsumerState<AutomationSettingsSection> createState() =>
      _AutomationSettingsSectionState();
}

class _AutomationSettingsSectionState
    extends ConsumerState<AutomationSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _autostart = false;
  int _runRetentionDays = 30;
  int _auditRetentionDays = 90;
  int _trashRetentionDays = 30;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final payload = await ref
          .read(runtimeHostClientProvider)
          .runtimeRequest('runtimeSettings.get');
      final automation = _asMap(_asMap(payload)['automation']);
      if (!mounted) {
        return;
      }
      setState(() {
        _autostart = automation['autostart'] == true;
        _runRetentionDays = _intOr(automation['runRetentionDays'], 30);
        _auditRetentionDays = _intOr(automation['auditRetentionDays'], 90);
        _trashRetentionDays = _intOr(automation['trashRetentionDays'], 30);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(runtimeHostClientProvider).runtimeRequest(
        'runtimeSettings.update',
        <String, Object?>{
          'automation': <String, Object?>{
            'autostart': _autostart,
            'runRetentionDays': _runRetentionDays,
            'auditRetentionDays': _auditRetentionDays,
            'trashRetentionDays': _trashRetentionDays,
          },
        },
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AleraEmptyState(
        title: 'Loading Automation Settings',
        message: 'Reading runtime automation settings.',
      );
    }
    if (_error != null && !_saving) {
      return AleraEmptyState(
        title: 'Automation Settings Unavailable',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    return AleraSettingsGroup(
      title: 'Automation History And Autostart',
      description: 'Keep scheduled work available without a window and control local retention.',
      children: <Widget>[
        SettingsSwitchRow(
          title: 'Start Automations At Login',
          description: 'Start the persistent local automation host when you sign in. This is off by default.',
          value: _autostart,
          onChanged: (value) {
            setState(() => _autostart = value);
            unawaited(_save());
          },
        ),
        SettingsIntegerRow(
          title: 'Run History Retention',
          description: 'Keep final runs for at most this many days.',
          value: _runRetentionDays,
          min: 1,
          max: 3650,
          step: 1,
          suffix: 'days',
          onChanged: (value) {
            setState(() => _runRetentionDays = value);
            unawaited(_save());
          },
        ),
        SettingsIntegerRow(
          title: 'Audit Retention',
          description:
              'Keep automation audit events for at most this many days.',
          value: _auditRetentionDays,
          min: 1,
          max: 3650,
          step: 1,
          suffix: 'days',
          onChanged: (value) {
            setState(() => _auditRetentionDays = value);
            unawaited(_save());
          },
        ),
        SettingsIntegerRow(
          title: 'Trash Retention',
          description:
              'Permanently remove trashed definitions after this many days.',
          value: _trashRetentionDays,
          min: 1,
          max: 3650,
          step: 1,
          suffix: 'days',
          onChanged: (value) {
            setState(() => _trashRetentionDays = value);
            unawaited(_save());
          },
        ),
      ],
    );
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
}

int _intOr(Object? value, int fallback) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;
