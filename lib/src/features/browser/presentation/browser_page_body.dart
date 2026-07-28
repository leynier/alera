import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:flutter/material.dart';

class BrowserPageBody extends StatelessWidget {
  const BrowserPageBody({
    super.key,
    required this.state,
    required this.surface,
    required this.onRetry,
    required this.onOpenExternally,
  });

  final BrowserPageState state;
  final Widget surface;
  final VoidCallback onRetry;
  final VoidCallback? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final availability = state.engineAvailability;
    if (!browserStateShowsNativeSurface(state) &&
        availability != BrowserEngineAvailability.available) {
      return ColoredBox(
        color: AleraTokens.bg,
        child: AleraEmptyState(
          icon: AleraIcons.insecure,
          title: 'Browser Engine Unavailable',
          message:
              state.capabilityReason ??
              'This Platform Does Not Meet The Browser Capability Gate.',
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
          title: 'Page Could Not Be Loaded',
          message:
              state.error?.message ??
              'Check The Address And Your Connection, Then Try Again.',
          action: Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            alignment: WrapAlignment.center,
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
          message: 'Search Or Enter An Address In The Bar Above.',
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
