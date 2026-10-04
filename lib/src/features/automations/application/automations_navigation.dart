import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automations_navigation.g.dart';

/// Where "New Automation" was started from. The origin is only context: it
/// never selects an execution target type.
class const AutomationAuthoringRequest({
  final String? originWorkspaceId,
  final String? projectId,
  final String? editId,
  final String? cloneId,
  final Map<String, Object?>? template,
});

class const AutomationsLocation({
  final bool visible = false,
  final AutomationScope scope = AutomationScope.all,
  final AutomationCatalogFilters filters = const AutomationCatalogFilters(),
  final String? selectedId,
  final String? selectedRunId,
  final AutomationAuthoringRequest? authoring,
  final int authoringSequence = 0,
}) {
  AutomationsLocation copyWith({
    bool? visible,
    AutomationScope? scope,
    AutomationCatalogFilters? filters,
    String? Function()? selectedId,
    String? Function()? selectedRunId,
    AutomationAuthoringRequest? Function()? authoring,
    int? authoringSequence,
  }) => AutomationsLocation(
    visible: visible ?? this.visible,
    scope: scope ?? this.scope,
    filters: filters ?? this.filters,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    selectedRunId: selectedRunId == null ? this.selectedRunId : selectedRunId(),
    authoring: authoring == null ? this.authoring : authoring(),
    authoringSequence: authoringSequence ?? this.authoringSequence,
  );
}

// Retain only navigation, never runtime snapshots or subscriptions.
@Riverpod(keepAlive: true)
class AutomationsNavigation extends _$AutomationsNavigation {
  @override
  AutomationsLocation build() => const AutomationsLocation();

  /// The Run Board and Automations share the shell's page slot.
  void open({AutomationScope? scope}) {
    ref.read(runBoardNavigationProvider.notifier).close();
    state = state.copyWith(
      visible: true,
      scope: scope,
      filters: scope == null ? null : const AutomationCatalogFilters(),
    );
  }

  void close() => state = state.copyWith(visible: false);

  void setScope(AutomationScope scope) => state = state.copyWith(scope: scope);

  void setFilters(AutomationCatalogFilters filters) =>
      state = state.copyWith(filters: filters);

  void clearFilters() =>
      state = state.copyWith(filters: const AutomationCatalogFilters());

  void select(String? id) =>
      state = state.copyWith(selectedId: () => id, selectedRunId: () => null);

  void selectRun(String automationId, String? runId) => state = state.copyWith(
    selectedId: () => automationId,
    selectedRunId: () => runId,
  );

  /// Opens the page and asks it to start the authoring flow once mounted.
  void startAuthoring(
    AutomationAuthoringRequest request, {
    AutomationScope? scope,
  }) {
    ref.read(runBoardNavigationProvider.notifier).close();
    state = state.copyWith(
      visible: true,
      scope: scope,
      authoring: () => request,
      authoringSequence: state.authoringSequence + 1,
    );
  }

  void consumeAuthoring() => state = state.copyWith(authoring: () => null);
}
