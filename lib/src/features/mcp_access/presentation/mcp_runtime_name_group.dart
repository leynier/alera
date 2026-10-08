import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:flutter/material.dart';

const double _kNameControlWidth = 340;

/// Runtime name editor. Presentational: the pane owns [controller], the rename
/// call, and the error it reports.
class const McpRuntimeNameGroup({
  super.key,
  required final McpAccessSettings settings,
  required final TextEditingController controller,
  required final bool saving,
  required final ValueChanged<String> onChanged,
  required final VoidCallback onRename,
  final String? error,
}) extends StatelessWidget {
  /// Whether the field holds a name that differs from the current one.
  static bool canRename(McpAccessSettings settings, String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed != settings.effectiveRuntimeName;
  }

  @override
  Widget build(BuildContext context) {
    final current = settings.effectiveRuntimeName;
    final enabled = !saving && canRename(settings, controller.text);
    return AleraSettingsGroup(
      title: 'Runtime Name',
      description:
          'MCP clients choose a runtime by this name. Names are unique within '
          'your Alera account.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Name',
          description: settings.runtimeName == null
              ? 'Currently "$current", taken from the host name.'
              : 'Currently "$current".',
          controlWidth: _kNameControlWidth,
          child: Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: controller,
                  hintText: current,
                  errorText: error,
                  enabled: !saving,
                  onChanged: onChanged,
                  onSubmitted: (_) {
                    if (enabled) {
                      onRename();
                    }
                  },
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton(
                onPressed: enabled ? onRename : null,
                child: Text(saving ? 'Renaming…' : 'Rename'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
