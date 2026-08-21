import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AgentProfileManagedEditor extends StatelessWidget {
  const AgentProfileManagedEditor({
    super.key,
    required this.adapter,
    required this.config,
    required this.models,
    required this.personas,
    required this.enabled,
    required this.onChanged,
    required this.onRefreshModels,
    required this.onRefreshPersonas,
    this.modelsLoading = false,
    this.personasLoading = false,
    this.discoveryError,
  });

  final AgentType adapter;
  final Map<String, Object?> config;
  final List<ManagedAgentOption> models;
  final List<ManagedAgentOption> personas;
  final bool enabled;
  final bool modelsLoading;
  final bool personasLoading;
  final String? discoveryError;
  final ValueChanged<Map<String, Object?>> onChanged;
  final VoidCallback? onRefreshModels;
  final VoidCallback? onRefreshPersonas;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      if (agentProfileSupportsCcsProfile(adapter))
        _textRow(
          title: 'CCS Profile',
          description:
              'Leave empty to run Claude directly. A profile launches ccs with '
              'the profile first and the same flags after it. CCS points '
              'CLAUDE_CONFIG_DIR at its own directory, so Alera agent status '
              'hooks reach that session only if the profile inherits them.',
          keyName: 'ccsProfile',
        ),
      if (agentProfileSupportsModel(adapter)) ...<Widget>[
        _choiceRow(
          title: 'Model',
          description: 'Leave as default to use the agent configuration.',
          keyName: 'model',
          options: models,
          filterable: true,
          trailing: onRefreshModels == null
              ? null
              : AleraIconButton(
                  tooltip: 'Refresh Models',
                  icon: modelsLoading ? AleraIcons.loading : AleraIcons.refresh,
                  onPressed: enabled && !modelsLoading ? onRefreshModels : null,
                ),
        ),
        _textRow(
          title: 'Exact Model ID',
          description: 'Use a model ID that is not in the discovered list.',
          keyName: 'model',
        ),
      ],
      if (agentProfileSupportsPersona(adapter)) ...<Widget>[
        _choiceRow(
          title: 'Persona',
          description: 'Select a known agent persona or enter an exact name.',
          keyName: 'agent',
          options: personas,
          filterable: true,
          trailing: onRefreshPersonas == null
              ? null
              : AleraIconButton(
                  tooltip: 'Refresh Personas',
                  icon: personasLoading
                      ? AleraIcons.loading
                      : AleraIcons.refresh,
                  onPressed: enabled && !personasLoading
                      ? onRefreshPersonas
                      : null,
                ),
        ),
        _textRow(
          title: 'Exact Persona',
          description: 'Use a persona name that is not in the discovered list.',
          keyName: 'agent',
        ),
      ],
      ..._adapterControls(),
    ];
    return AleraSettingsGroup(
      title: 'Managed Options',
      description:
          'Alera builds the interactive command from these agent-specific settings.',
      children: <Widget>[
        ...controls,
        if (discoveryError != null)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              discoveryError!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AleraTokens.warning),
            ),
          ),
      ],
    );
  }

  List<Widget> _adapterControls() {
    return switch (adapter) {
      AgentType.codex => <Widget>[
        _choiceRow(
          title: 'Reasoning Effort',
          keyName: 'effort',
          options: codexEffortOptions,
        ),
        _choiceRow(
          title: 'Plan Mode Reasoning Effort',
          description:
              'Applies only while Codex is in plan mode, which is entered with '
              'Shift+Tab or /plan. Codex has no way to start there.',
          keyName: 'planModeEffort',
          options: codexEffortOptions,
        ),
        _choiceRow(
          title: 'Sandbox',
          keyName: 'sandbox',
          options: codexSandboxOptions,
        ),
        _choiceRow(
          title: 'Approval Policy',
          keyName: 'approvalPolicy',
          options: codexApprovalOptions,
        ),
        _boolRow(
          title: 'Web Search',
          description: 'Allow Codex to search the web.',
          keyName: 'webSearch',
        ),
        _boolRow(
          title: 'Bypass All Protections',
          description: 'Bypass both approval prompts and sandbox isolation.',
          keyName: 'bypassApprovalsAndSandbox',
        ),
      ],
      AgentType.claude => <Widget>[
        _choiceRow(
          title: 'Reasoning Effort',
          keyName: 'effort',
          options: claudeEffortOptions,
        ),
        _choiceRow(
          title: 'Permission Mode',
          keyName: 'permissionMode',
          options: claudePermissionOptions,
        ),
        _boolRow(
          title: 'Allow Skip Permissions',
          description:
              'Make bypass available during the session without starting in '
              'it. Use the Bypass Permissions mode above to start in it.',
          keyName: 'allowSkipPermissions',
        ),
      ],
      AgentType.copilot => <Widget>[
        _choiceRow(
          title: 'Reasoning Effort',
          keyName: 'effort',
          options: copilotEffortOptions,
        ),
        _choiceRow(title: 'Mode', keyName: 'mode', options: copilotModeOptions),
        _choiceRow(
          title: 'Context',
          keyName: 'context',
          options: copilotContextOptions,
        ),
        _boolRow(
          title: 'Allow All',
          description: 'Allow tools and paths without individual prompts.',
          keyName: 'allowAll',
        ),
        _numberRow(
          title: 'Maximum AI Credits',
          keyName: 'maxAiCredits',
          decimal: true,
        ),
        _numberRow(
          title: 'Maximum Autopilot Continues',
          keyName: 'maxAutopilotContinues',
        ),
        _boolRow(
          title: 'Do Not Ask User',
          description: 'Continue without asking the user for input.',
          keyName: 'noAskUser',
        ),
      ],
      AgentType.cursor => <Widget>[
        _choiceRow(title: 'Mode', keyName: 'mode', options: cursorModeOptions),
        _choiceRow(
          title: 'Review Mode',
          keyName: 'permissionMode',
          options: cursorPermissionOptions,
        ),
        _choiceRow(
          title: 'Sandbox',
          keyName: 'sandbox',
          options: cursorSandboxOptions,
        ),
        _boolRow(
          title: 'Trust Workspace',
          description: 'Trust the workspace without an interactive prompt.',
          keyName: 'trustWorkspace',
        ),
      ],
      AgentType.agy => <Widget>[
        _choiceRow(
          title: 'Reasoning Effort',
          keyName: 'effort',
          options: basicEffortOptions,
        ),
        _choiceRow(title: 'Mode', keyName: 'mode', options: agyModeOptions),
        _boolRow(
          title: 'Skip Permissions',
          description: 'Run without Antigravity permission checks.',
          keyName: 'skipPermissions',
        ),
        _boolRow(
          title: 'Sandbox',
          description: 'Enable the Antigravity sandbox.',
          keyName: 'sandbox',
        ),
      ],
      AgentType.opencode || AgentType.opencode2 => <Widget>[
        _boolRow(
          title: 'Auto Approve',
          description: 'Approve OpenCode actions automatically.',
          keyName: 'autoApprove',
        ),
      ],
      AgentType.pi => <Widget>[
        _choiceRow(
          title: 'Thinking',
          keyName: 'thinking',
          options: piThinkingOptions,
        ),
        _choiceRow(
          title: 'Project Trust',
          keyName: 'projectTrust',
          options: piTrustOptions,
        ),
      ],
      AgentType.amp => <Widget>[
        _choiceRow(
          title: 'Mode',
          description:
              'Amp permission rules continue to come from the global Amp configuration.',
          keyName: 'mode',
          options: ampModeOptions,
        ),
        _boolRow(
          title: 'Fast Mode',
          description: 'Prefer lower latency responses.',
          keyName: 'fast',
        ),
      ],
      AgentType.grok => <Widget>[
        _choiceRow(
          title: 'Reasoning Effort',
          keyName: 'effort',
          options: grokEffortOptions,
        ),
        _choiceRow(
          title: 'Permission Mode',
          keyName: 'permissionMode',
          options: grokPermissionOptions,
        ),
        _choiceRow(
          title: 'Sandbox',
          keyName: 'sandbox',
          options: grokSandboxOptions,
        ),
        _boolRow(
          title: 'Disable Web Search',
          description: 'Disable Grok Build web search and web fetch tools.',
          keyName: 'disableWebSearch',
        ),
      ],
      AgentType.fx => <Widget>[
        _boolRow(
          title: 'Resume Latest Session',
          description: 'Resume the latest fx session in this workspace.',
          keyName: 'resumeLast',
        ),
        _boolRow(
          title: 'Ignore Additional Directories',
          description: 'Do not load additional directories configured by fx.',
          keyName: 'noAdditionalDirs',
        ),
        _boolRow(
          title: 'Record Session',
          description: 'Record the fx session for later inspection.',
          keyName: 'record',
        ),
      ],
    };
  }

  Widget _choiceRow({
    required String title,
    required String keyName,
    required List<ManagedAgentOption> options,
    String? description,
    bool filterable = false,
    Widget? trailing,
  }) {
    final selected = config[keyName] is String ? config[keyName] as String : '';
    final entries = <ManagedAgentOption>[
      const ManagedAgentOption('', 'Agent Default'),
      ...options,
    ];
    final hasSelected = entries.any((option) => option.value == selected);
    if (selected.isNotEmpty && !hasSelected) {
      entries.add(ManagedAgentOption(selected, 'Custom: $selected'));
    }
    return AleraSettingRow(
      title: title,
      description: description,
      child: Row(
        children: <Widget>[
          Expanded(
            child: AleraDropdownField<String>(
              key: ValueKey<String>('Managed:$keyName:$selected'),
              value: selected,
              entries: <AleraDropdownFieldEntry<String>>[
                for (final option in entries)
                  AleraDropdownFieldEntry<String>(
                    value: option.value,
                    label: option.label,
                  ),
              ],
              enabled: enabled,
              filterable: filterable,
              onChanged: (value) =>
                  _setValue(keyName, value.isEmpty ? null : value),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _textRow({
    required String title,
    required String description,
    required String keyName,
  }) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: _ManagedTextField(
        value: config[keyName]?.toString() ?? '',
        enabled: enabled,
        onChanged: (value) =>
            _setValue(keyName, value.trim().isEmpty ? null : value.trim()),
      ),
    );
  }

  Widget _numberRow({
    required String title,
    required String keyName,
    bool decimal = false,
  }) {
    return AleraSettingRow(
      title: title,
      description: 'Leave empty to use the agent default.',
      child: _ManagedTextField(
        value: config[keyName]?.toString() ?? '',
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        onChanged: (value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            _setValue(keyName, null);
            return;
          }
          final parsed = decimal
              ? double.tryParse(trimmed)
              : int.tryParse(trimmed);
          if (parsed != null) {
            _setValue(keyName, parsed);
          }
        },
      ),
    );
  }

  Widget _boolRow({
    required String title,
    required String keyName,
    String? description,
  }) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: AleraCheckbox(
          value: config[keyName] == true,
          enabled: enabled,
          onChanged: (value) => _setValue(keyName, value ? true : null),
        ),
      ),
    );
  }

  void _setValue(String key, Object? value) {
    final next = <String, Object?>{...config};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    onChanged(next);
  }
}

class _ManagedTextField extends StatefulWidget {
  const _ManagedTextField({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.keyboardType,
    this.inputFormatters,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_ManagedTextField> createState() => _ManagedTextFieldState();
}

class _ManagedTextFieldState extends State<_ManagedTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_ManagedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: _controller,
      enabled: widget.enabled,
      dense: true,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
    );
  }
}
