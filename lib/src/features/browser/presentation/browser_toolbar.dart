import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter/material.dart';

class const BrowserToolbar({
  super.key,
  required final BrowserPageState state,
  required final TextEditingController addressController,
  required final FocusNode addressFocusNode,
  required final String profileLabel,
  required final VoidCallback? onBack,
  required final VoidCallback? onForward,
  required final VoidCallback? onStopOrReload,
  required final ValueChanged<String> onSubmitAddress,
  required final VoidCallback onShowSecurity,
  required final VoidCallback onSelectProfile,
  required final VoidCallback onShowDownloads,
  final VoidCallback? onAnnotate,
  required final VoidCallback? onOpenDevTools,
  required final VoidCallback? onOpenExternally,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AleraTokens.surface,
      child: SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= AleraTokens.wideContentBreakpoint;
            return Stack(
              fit: .expand,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                  ),
                  child: Row(
                    children: <Widget>[
                      AleraIconButton(
                        tooltip: 'Go Back',
                        icon: AleraIcons.back,
                        minSize: AleraTokens.space24 + AleraTokens.space4,
                        onPressed: onBack,
                      ),
                      AleraIconButton(
                        tooltip: 'Go Forward',
                        icon: AleraIcons.forward,
                        minSize: AleraTokens.space24 + AleraTokens.space4,
                        onPressed: onForward,
                      ),
                      AleraIconButton(
                        tooltip: state.isLoading
                            ? 'Stop Loading'
                            : 'Reload Page',
                        icon: state.isLoading
                            ? AleraIcons.stop
                            : AleraIcons.refresh,
                        minSize: AleraTokens.space24 + AleraTokens.space4,
                        onPressed: onStopOrReload,
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      AleraIconButton(
                        tooltip: _securityTooltip(state.security),
                        icon: _securityIcon(state.security.level),
                        iconColor: _securityColor(state.security.level),
                        minSize: AleraTokens.space24 + AleraTokens.space4,
                        onPressed: onShowSecurity,
                      ),
                      const SizedBox(width: AleraTokens.space4),
                      Expanded(
                        child: AleraTextField(
                          controller: addressController,
                          focusNode: addressFocusNode,
                          dense: true,
                          denseHeight: AleraTokens.space32,
                          // The constrained decorator centers its text line
                          // only when the editable content uses bottom alignment.
                          textAlignVertical: .bottom,
                          // Toolbar chrome is surface; dense defaults to a
                          // surface fill meant for surface-variant sidebars.
                          fillColor: AleraTokens.surfaceVariant,
                          hintText: 'Search or enter address',
                          onSubmitted: onSubmitAddress,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      AleraIconButton(
                        tooltip: 'Browser Profile: $profileLabel',
                        icon: AleraIcons.profile,
                        onPressed: onSelectProfile,
                      ),
                      _BrowserDownloadsButton(
                        count: state.downloads
                            .where((download) => !download.isTerminal)
                            .length,
                        onPressed: onShowDownloads,
                      ),
                      AleraIconButton(
                        tooltip: 'Annotate Page',
                        icon: AleraIcons.edit,
                        onPressed: onAnnotate,
                      ),
                      if (wide)
                        AleraIconButton(
                          tooltip: 'Open DevTools',
                          icon: AleraIcons.devTools,
                          onPressed: onOpenDevTools,
                        ),
                      AleraIconButton(
                        tooltip: 'Open Externally',
                        icon: AleraIcons.external,
                        onPressed: onOpenExternally,
                      ),
                    ],
                  ),
                ),
                if (state.isLoading)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progressWidth(state.loadProgress),
                      child: const SizedBox(
                        height: AleraTokens.space2,
                        child: ColoredBox(color: AleraTokens.info),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class const _BrowserDownloadsButton({
  required final int count,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: .none,
      children: <Widget>[
        AleraIconButton(
          tooltip: count == 0 ? 'Downloads' : 'Downloads ($count Active)',
          icon: count == 0 ? AleraIcons.download : AleraIcons.downloading,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            top: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AleraTokens.info,
                shape: .circle,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AleraTokens.space12,
                  minHeight: AleraTokens.space12,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space2,
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: .center,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AleraTokens.onAccent),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

double _progressWidth(double? progress) {
  if (progress == null || !progress.isFinite) {
    return 0.08;
  }
  return progress.clamp(0.02, 1).toDouble();
}

IconData _securityIcon(BrowserSecurityLevel level) {
  return switch (level) {
    BrowserSecurityLevel.secure ||
    BrowserSecurityLevel.local => AleraIcons.secure,
    BrowserSecurityLevel.insecure ||
    BrowserSecurityLevel.certificateFailure => AleraIcons.insecure,
    BrowserSecurityLevel.unknown => AleraIcons.info,
  };
}

Color _securityColor(BrowserSecurityLevel level) {
  return switch (level) {
    BrowserSecurityLevel.secure => AleraTokens.success,
    BrowserSecurityLevel.local => AleraTokens.info,
    BrowserSecurityLevel.insecure ||
    BrowserSecurityLevel.certificateFailure => AleraTokens.warning,
    BrowserSecurityLevel.unknown => AleraTokens.foregroundFaint,
  };
}

String _securityTooltip(BrowserSecurityState security) {
  final origin = security.origin;
  final label = switch (security.level) {
    BrowserSecurityLevel.secure => 'Secure Connection',
    BrowserSecurityLevel.local => 'Local Connection',
    BrowserSecurityLevel.insecure => 'Insecure Connection',
    BrowserSecurityLevel.certificateFailure => 'Certificate Failure',
    BrowserSecurityLevel.unknown => 'Connection Details',
  };
  return origin == null || origin.isEmpty ? label : '$label - $origin';
}
