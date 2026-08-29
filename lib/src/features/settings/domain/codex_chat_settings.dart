part of 'alera_settings.dart';

@MappableClass()
class CodexChatSettings with CodexChatSettingsMappable {
  const CodexChatSettings({
    this.selectedModel,
    this.reasoningEffort = 'medium',
    this.speedMode = 'normal',
    this.permissionMode = 'on-request',
    this.planMode = false,
  });

  final String? selectedModel;
  final String reasoningEffort;
  final String speedMode;
  final String permissionMode;
  final bool planMode;

  static const CodexChatSettings defaults = CodexChatSettings();

  factory CodexChatSettings.fromJson(Map<String, Object?> json) =>
      CodexChatSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
