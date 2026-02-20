import 'dart:convert';

import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:alera/src/shared/models/contracts.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.plannerModel,
    required this.executorModel,
    required this.approvalPolicy,
  });

  final String plannerModel;
  final String executorModel;
  final ApprovalPolicy approvalPolicy;
}

class SettingsService {
  SettingsService(this._preferencesStore);

  final StringStore _preferencesStore;

  static const String _plannerModelKey = 'settings.model.planner';
  static const String _executorModelKey = 'settings.model.executor';
  static const String _approvalPolicyKey = 'settings.approval.policy';

  Future<SettingsSnapshot> load() async {
    final plannerModel =
        await _preferencesStore.getString(_plannerModelKey) ?? 'gpt-5';
    final executorModel =
        await _preferencesStore.getString(_executorModelKey) ?? 'gpt-5-codex';

    final policyRaw = await _preferencesStore.getString(_approvalPolicyKey);
    final policy = _decodePolicy(policyRaw) ?? ApprovalPolicy.ask;

    return SettingsSnapshot(
      plannerModel: plannerModel,
      executorModel: executorModel,
      approvalPolicy: policy,
    );
  }

  Future<void> save(SettingsSnapshot snapshot) async {
    await _preferencesStore.setString(_plannerModelKey, snapshot.plannerModel);
    await _preferencesStore.setString(_executorModelKey, snapshot.executorModel);
    await _preferencesStore.setString(
      _approvalPolicyKey,
      jsonEncode(snapshot.approvalPolicy.name),
    );
  }

  ApprovalPolicy? _decodePolicy(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! String) {
      return null;
    }

    for (final value in ApprovalPolicy.values) {
      if (value.name == decoded) {
        return value;
      }
    }
    return null;
  }
}
