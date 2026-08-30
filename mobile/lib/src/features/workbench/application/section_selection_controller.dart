import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:logging/logging.dart';

part 'section_selection_controller.g.dart';

final _logger = Logger('SectionSelectionController');

class SectionSelectionState {
  const SectionSelectionState({
    required this.sections,
    this.selected = '',
    this.name = '',
    this.saving = false,
    this.error = '',
  });
  final List<WorkspaceSectionSummary> sections;
  final String selected;
  final String name;
  final bool saving;
  final String error;
  SectionSelectionState copyWith({
    List<WorkspaceSectionSummary>? sections,
    String? selected,
    String? name,
    bool? saving,
    String? error,
  }) => SectionSelectionState(
    sections: sections ?? this.sections,
    selected: selected ?? this.selected,
    name: name ?? this.name,
    saving: saving ?? this.saving,
    error: error ?? this.error,
  );
}

@riverpod
class SectionSelectionController extends _$SectionSelectionController {
  @override
  Future<SectionSelectionState> build(
    String hostId,
    String workspaceId,
    String? initialSectionId,
  ) async {
    try {
      final client = await ref.watch(workspaceClientProvider(hostId).future);
      final sections = await (client as MobileWorkspaceSectionClient)
          .listWorkspaceSections();
      return SectionSelectionState(
        sections: sections,
        selected: sections.any((section) => section.id == initialSectionId)
            ? initialSectionId!
            : '',
      );
    } catch (error, stack) {
      _logger.warning('Could not load workspace sections', error, stack);
      rethrow;
    }
  }

  void select(String value) {
    final current = state.value;
    if (current != null && !current.saving) {
      state = AsyncData(current.copyWith(selected: value, error: ''));
    }
  }

  void nameChanged(String value) {
    final current = state.value;
    if (current != null && !current.saving) {
      state = AsyncData(current.copyWith(name: value, error: ''));
    }
  }

  Future<bool> save() async {
    final current = state.value;
    if (current == null || current.saving) return false;
    final creating = current.selected == '__new__';
    final name = current.name.trim();
    if (creating &&
        (name.isEmpty ||
            name.toLowerCase() == 'others' ||
            current.sections.any(
              (section) => section.name.toLowerCase() == name.toLowerCase(),
            ))) {
      state = AsyncData(
        current.copyWith(
          error: 'Enter a unique section name other than Others.',
        ),
      );
      return false;
    }
    state = AsyncData(current.copyWith(saving: true, error: ''));
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      final sections = client as MobileWorkspaceSectionClient;
      if (creating) {
        await sections.createWorkspaceSection(name, workspaceId);
      } else {
        await sections.setWorkspaceSection(
          workspaceId,
          current.selected.isEmpty ? null : current.selected,
        );
      }
      if (ref.mounted) {
        state = AsyncData(current.copyWith(saving: false, error: ''));
        ref.invalidate(workspaceListControllerProvider(hostId));
      }
      return true;
    } catch (error, stack) {
      _logger.warning('Could not save workspace section', error, stack);
      if (!ref.mounted) return false;
      var refreshed = current.sections;
      try {
        final client = await ref.read(workspaceClientProvider(hostId).future);
        refreshed = await (client as MobileWorkspaceSectionClient)
            .listWorkspaceSections();
      } catch (refreshError, refreshStack) {
        _logger.warning(
          'Could not refresh workspace sections after saving failed',
          refreshError,
          refreshStack,
        );
      }
      if (ref.mounted) {
        state = AsyncData(
          current.copyWith(
            sections: refreshed,
            saving: false,
            error: '$error',
            selected:
                creating ||
                    refreshed.any((section) => section.id == current.selected)
                ? current.selected
                : '',
          ),
        );
      }
      return false;
    }
  }
}
