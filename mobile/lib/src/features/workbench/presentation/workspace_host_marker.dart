import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:flutter/material.dart';

/// Operating system glyph of the host that owns a workspace. A long press
/// shows the host alias, and screen readers get it as the label.
class const WorkspaceHostMarker({
  super.key,
  required final MobileWorkspaceHost host,
  final double size = AleraTokens.iconSm,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: host.label,
      // The icon carries the label; the tooltip would read it a second time.
      excludeFromSemantics: true,
      child: AleraHostOsIcon(
        os: host.os,
        size: size,
        semanticLabel: 'Host ${host.label}',
      ),
    );
  }
}

/// A workspace name for a screen title, led by the host marker when the
/// workspace lives on another host.
class const WorkspaceHostTitle({
  super.key,
  required final String name,
  final MobileWorkspaceHost? host,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final title = Text(name, overflow: .ellipsis);
    final owner = host;
    if (owner == null) {
      return title;
    }
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        WorkspaceHostMarker(
          key: const Key('workspace-title-host'),
          host: owner,
          size: AleraTokens.space16,
        ),
        const SizedBox(width: AleraTokens.space8),
        Flexible(child: title),
      ],
    );
  }
}
