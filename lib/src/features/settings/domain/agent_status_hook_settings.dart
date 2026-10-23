part of 'alera_settings.dart';

/// OpenCode v1 and OpenCode 2 used to have separate toggles; both install as
/// `opencode` now. Either stored toggle enables OpenCode, and the encoded form
/// keeps an `opencode2` copy because the app can attach to an older runtime,
/// which still installs its OpenCode 2 plugin from that key.
class const _LegacyOpenCode2HookToggleHook() extends MappingHook {
  static const String _legacyKey = 'opencode2';

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map || !value.containsKey(_legacyKey)) {
      return value;
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key != _legacyKey) entry.key.toString(): entry.value,
      'opencode': value['opencode'] == true || value[_legacyKey] == true,
    };
  }

  @override
  Object? afterEncode(Object? value) {
    if (value is! Map) {
      return value;
    }
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
      _legacyKey: value['opencode'] == true,
    };
  }
}

@MappableClass(hook: _LegacyOpenCode2HookToggleHook())
class const AgentStatusHookSettings({
  this.codex = false,
  this.claude = false,
  this.copilot = false,
  this.cursor = false,
  this.agy = false,
  this.opencode = false,
  this.pi = false,
  this.amp = false,
  this.grok = false,
  this.fx = false,
}) with AgentStatusHookSettingsMappable {
  final bool codex;
  final bool claude;
  final bool copilot;
  final bool cursor;
  final bool agy;
  final bool opencode;
  final bool pi;
  final bool amp;
  final bool grok;
  final bool fx;

  bool get anyEnabled =>
      codex ||
      claude ||
      copilot ||
      cursor ||
      agy ||
      opencode ||
      pi ||
      amp ||
      grok ||
      fx;

  static const AgentStatusHookSettings defaults = AgentStatusHookSettings();

  factory fromJson(Map<String, Object?> json) =>
      AgentStatusHookSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
