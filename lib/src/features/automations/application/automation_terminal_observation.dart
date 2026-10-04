import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_terminal_observation.g.dart';

/// Tabs this client took over, so a re-attach uses the normal mode at once
/// instead of waiting for the tab record to carry the takeover mark.
@Riverpod(keepAlive: true)
class AutomationTakenOverTabs extends _$AutomationTakenOverTabs {
  @override
  Set<String> build() => const <String>{};

  void mark(String tabId) => state = <String>{...state, tabId};
}

/// An automation-owned tab attaches read-only until somebody takes it over.
bool automationTabIsObserved(
  Map<String, Object?> tabPayload,
  String tabId,
  Set<String> takenOverTabs,
) =>
    tabPayload['automationOwned'] == true &&
    tabPayload['automationTakenOver'] != true &&
    !takenOverTabs.contains(tabId);
