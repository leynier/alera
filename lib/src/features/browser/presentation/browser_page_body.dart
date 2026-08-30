import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:flutter/material.dart';

class const BrowserPageBody({
  super.key,
  required final BrowserPageState state,
  required final Widget surface,
  required final VoidCallback onRetry,
  required final VoidCallback? onOpenExternally,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final availability = state.engineAvailability;
    if (!browserStateShowsNativeSurface(state) &&
        availability != BrowserEngineAvailability.available) {
      return ColoredBox(
        color: AleraTokens.bg,
        child: AleraEmptyState(
          icon: AleraIcons.insecure,
          title: 'Browser engine unavailable',
          message:
              state.capabilityReason ??
              'This platform does not meet the browser capability gate.',
          action: onOpenExternally == null
              ? null
              : OutlinedButton.icon(
                  onPressed: onOpenExternally,
                  icon: const Icon(AleraIcons.external),
                  label: const Text('Open Externally'),
                ),
        ),
      );
    }
    if (!browserStateShowsNativeSurface(state) &&
        state.loadPhase == BrowserLoadPhase.failed) {
      return ColoredBox(
        color: AleraTokens.bg,
        child: AleraEmptyState(
          icon: AleraIcons.error,
          title: 'Page could not be loaded',
          message:
              state.error?.message ??
              'Check the address and your connection, then try again.',
          action: Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            alignment: .center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(AleraIcons.refresh),
                label: const Text('Try Again'),
              ),
              if (onOpenExternally != null)
                OutlinedButton.icon(
                  onPressed: onOpenExternally,
                  icon: const Icon(AleraIcons.external),
                  label: const Text('Open Externally'),
                ),
            ],
          ),
        ),
      );
    }
    if (!browserStateShowsNativeSurface(state)) {
      return const ColoredBox(
        color: AleraTokens.bg,
        child: AleraEmptyState(
          icon: AleraIcons.public,
          title: 'Start Browsing',
          message: 'Search or enter an address in the bar above.',
        ),
      );
    }
    return ColoredBox(color: AleraTokens.bg, child: surface);
  }
}

bool browserStateShowsNativeSurface(BrowserPageState state) =>
    state.engineAvailability == BrowserEngineAvailability.available &&
    state.loadPhase != BrowserLoadPhase.failed &&
    state.url.toString() != 'about:blank';
