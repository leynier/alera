import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const AutomationProfilePolicySection({
  required final String profileId,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AutomationProfilePolicySection> createState() =>
      _AutomationProfilePolicySectionState();
}

class _AutomationProfilePolicySectionState
    extends ConsumerState<AutomationProfilePolicySection> {
  bool _loading = true;
  bool _saving = false;
  bool _mayActivateOrEditActive = false;
  bool _mayExecute = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final payload = await ref.read(runtimeHostClientProvider).runtimeRequest(
        'automation.policy',
        <String, Object?>{'kind': 'agent', 'profileId': widget.profileId},
      );
      final policy = _asMap(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _mayActivateOrEditActive = policy['mayActivateOrEditActive'] == true;
        _mayExecute = policy['mayExecute'] == true;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
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
        'automation.policy',
        <String, Object?>{
          'kind': 'agent',
          'profileId': widget.profileId,
          'policy': <String, Object?>{
            'mayActivateOrEditActive': _mayActivateOrEditActive,
            'mayExecute': _mayExecute,
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
      return const Padding(
        padding: EdgeInsets.all(AleraTokens.space16),
        child: Text('Loading automation policy...'),
      );
    }
    if (_error != null && !_saving) {
      return AleraEmptyState(
        title: 'Automation Policy Unavailable',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    return AleraSettingsGroup(
      title: 'Automation Permissions',
      description: 'Choose whether this profile may administer active definitions and whether it may execute them.',
      children: <Widget>[
        SettingsSwitchRow(
          title: 'May Activate Or Edit Active Automations',
          description: 'Allow a managed agent using this profile to activate or edit an active definition.',
          value: _mayActivateOrEditActive,
          onChanged: (value) {
            setState(() => _mayActivateOrEditActive = value);
            unawaited(_save());
          },
        ),
        SettingsSwitchRow(
          title: 'May Execute Automations',
          description: 'Opt this profile into scheduled and manual automation execution.',
          value: _mayExecute,
          onChanged: (value) {
            setState(() => _mayExecute = value);
            unawaited(_save());
          },
        ),
      ],
    );
  }
}

class const AutomationProjectPolicySection({
  required final String projectId,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AutomationProjectPolicySection> createState() =>
      _AutomationProjectPolicySectionState();
}

class _AutomationProjectPolicySectionState
    extends ConsumerState<AutomationProjectPolicySection> {
  bool _loading = true;
  bool _saving = false;
  bool _localApproved = false;
  bool _restrictive = false;
  bool _repoDeclared = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final payload = await ref.read(runtimeHostClientProvider).runtimeRequest(
        'automation.policy',
        <String, Object?>{'kind': 'project', 'projectId': widget.projectId},
      );
      final policy = _asMap(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _localApproved = policy['localApproved'] == true;
        _restrictive = policy['restrictive'] == true;
        _repoDeclared = policy['repoDeclared'] == true;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
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
        'automation.policy',
        <String, Object?>{
          'kind': 'project',
          'projectId': widget.projectId,
          'policy': <String, Object?>{
            'localApproved': _localApproved,
            'restrictive': _restrictive,
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
      return const Padding(
        padding: EdgeInsets.all(AleraTokens.space16),
        child: Text('Loading automation policy...'),
      );
    }
    if (_error != null && !_saving) {
      return AleraEmptyState(
        title: 'Project Automation Policy Unavailable',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    return AleraSettingsGroup(
      title: 'Automation Policy',
      description: 'Repository declaration is read from alera.toml. Local approval can only restrict execution.',
      children: <Widget>[
        SettingsSwitchRow(
          title: 'Repository Declares Automations',
          description: _repoDeclared
              ? 'The repository declares automation use in alera.toml.'
              : 'Add an automation declaration to alera.toml before execution.',
          value: _repoDeclared,
          onChanged: null,
        ),
        SettingsSwitchRow(
          title: 'Require Local Approval',
          description: 'Require an explicit human approval in addition to the repository declaration.',
          value: _restrictive,
          onChanged: (value) {
            setState(() => _restrictive = value);
            unawaited(_save());
          },
        ),
        SettingsSwitchRow(
          title: 'Local Approval Granted',
          description: 'Grant the local approval required by a restrictive project policy.',
          value: _localApproved,
          onChanged: (value) {
            setState(() => _localApproved = value);
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
