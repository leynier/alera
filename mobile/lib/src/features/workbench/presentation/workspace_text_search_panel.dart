import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_text_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_search_rows.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_text_search_panel_inputs.dart';
part 'workspace_text_search_panel_results.dart';

enum _SearchViewOption { viewMode, collapseAll, includeIgnored }

class const WorkspaceTextSearchPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceTextSearchPanel> createState() =>
      _WorkspaceTextSearchPanelState();
}

class _WorkspaceTextSearchPanelState
    extends ConsumerState<WorkspaceTextSearchPanel> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _replacement = TextEditingController();
  final TextEditingController _include = TextEditingController();
  final TextEditingController _exclude = TextEditingController();
  bool _replaceVisible = false;
  bool _filtersVisible = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(_provider);
    _replaceVisible = state.replacement.isNotEmpty;
    _filtersVisible =
        state.includePattern.isNotEmpty || state.excludePattern.isNotEmpty;
  }

  @override
  void dispose() {
    _query.dispose();
    _replacement.dispose();
    _include.dispose();
    _exclude.dispose();
    super.dispose();
  }

  WorkspaceTextSearchControllerProvider get _provider =>
      workspaceTextSearchControllerProvider(widget.hostId, widget.workspaceId);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final client = ref.watch(workspaceClientProvider(widget.hostId)).value;
    final canReplace = switch (client) {
      final MobileWorkspacePanelsClient panels =>
        panels.supportsWorkspaceReplace,
      _ => false,
    };
    _sync(_query, state.query);
    _sync(_replacement, state.replacement);
    _sync(_include, state.includePattern);
    _sync(_exclude, state.excludePattern);
    final replaceVisible = canReplace && _replaceVisible;
    return Column(
      children: <Widget>[
        _SearchInputs(
          state: state,
          query: _query,
          replacement: _replacement,
          include: _include,
          exclude: _exclude,
          canReplace: canReplace,
          replaceVisible: replaceVisible,
          filtersVisible: _filtersVisible,
          notifier: notifier,
          onToggleReplace: () =>
              setState(() => _replaceVisible = !_replaceVisible),
          onToggleFilters: () =>
              setState(() => _filtersVisible = !_filtersVisible),
          onShowViewOptions: () => unawaited(_showViewOptions(state)),
          onReplaceAll: state.canReplaceAll
              ? () => unawaited(_replace(const <String>[], all: true))
              : null,
        ),
        if (state.searching || state.replacing)
          const LinearProgressIndicator(minHeight: AleraTokens.space2),
        Expanded(
          child: _Results(
            state: state,
            replaceVisible: replaceVisible,
            notifier: notifier,
            onOpenMatch: _openMatch,
            onReplace: (matchIds) => unawaited(_replace(matchIds, all: false)),
          ),
        ),
      ],
    );
  }

  Future<void> _showViewOptions(WorkspaceTextSearchState state) async {
    final notifier = ref.read(_provider.notifier);
    final choice = await showAleraActionSheet<_SearchViewOption>(
      context,
      entries: <AleraActionSheetEntry<_SearchViewOption>>[
        AleraActionSheetEntry<_SearchViewOption>(
          value: .viewMode,
          label: state.viewAsTree ? 'View as List' : 'View as Tree',
          leading: Icon(
            state.viewAsTree ? AleraIcons.listView : AleraIcons.treeView,
          ),
        ),
        if (state.result?.files.isNotEmpty ?? false)
          AleraActionSheetEntry<_SearchViewOption>(
            value: .collapseAll,
            label: state.allResultsCollapsed ? 'Expand All' : 'Collapse All',
            leading: Icon(
              state.allResultsCollapsed
                  ? AleraIcons.expandAll
                  : AleraIcons.collapseAll,
            ),
          ),
        AleraActionSheetEntry<_SearchViewOption>(
          value: .includeIgnored,
          label: state.includeIgnored
              ? 'Ignore Ignored Files'
              : 'Search Ignored Files',
          leading: Icon(
            state.includeIgnored ? AleraIcons.hidden : AleraIcons.visible,
          ),
        ),
      ],
    );
    switch (choice) {
      case _SearchViewOption.viewMode:
        notifier.toggleViewAsTree();
      case _SearchViewOption.collapseAll:
        notifier.toggleAllResultsCollapsed();
      case _SearchViewOption.includeIgnored:
        notifier.toggleIncludeIgnored();
      case null:
        break;
    }
  }

  Future<void> _replace(Iterable<String> matchIds, {required bool all}) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = ref.read(_provider);
    if (all) {
      final matches = state.result?.totalMatches ?? 0;
      final files = state.result?.files.length ?? 0;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: 'Replace All',
          message:
              'Replace ${_count(matches, 'match', 'matches')} in ${_count(files, 'file', 'files')} with "${state.replacement}"? This writes the files on the paired computer.',
          confirmLabel: 'Replace',
          destructive: true,
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    String message;
    try {
      final result = await ref
          .read(_provider.notifier)
          .replaceMatches(matchIds);
      message =
          workspaceSearchReplaceConflictMessage(result) ??
          'Replaced ${_count(result.matchesReplaced, 'match', 'matches')}.';
    } on StateError catch (error) {
      message = error.message;
    } on UnsupportedError catch (error) {
      message = error.message ?? 'Replace is unavailable.';
    } on Object catch (error) {
      message = 'Replace failed: $error';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMatch(
    MobileWorkspaceSearchFile file,
    MobileWorkspaceSearchMatch match,
  ) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceFileViewerScreen(
            hostId: widget.hostId,
            workspaceId: widget.workspaceId,
            relativePath: file.relativePath,
            highlightLine: match.line,
          ),
        ),
      ),
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: .collapsed(offset: value.length),
    );
  }
}

String _count(int value, String singular, String plural) =>
    '$value ${value == 1 ? singular : plural}';
