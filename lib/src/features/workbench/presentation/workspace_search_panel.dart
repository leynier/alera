import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_search_panel_feedback.dart';
part 'workspace_search_panel_inputs.dart';
part 'workspace_search_panel_results.dart';
part 'workspace_search_panel_toolbar.dart';
part 'workspace_search_panel_widgets.dart';

class WorkspaceSearchMatchTarget {
  const WorkspaceSearchMatchTarget({
    required this.relativePath,
    required this.line,
    required this.column,
    required this.matchLength,
  });

  final String relativePath;
  final int line;
  final int column;
  final int matchLength;
}

class WorkspaceSearchPanel extends ConsumerStatefulWidget {
  const WorkspaceSearchPanel({
    super.key,
    required this.workspace,
    required this.onOpenMatch,
  });

  final Workspace workspace;
  final ValueChanged<WorkspaceSearchMatchTarget> onOpenMatch;

  @override
  ConsumerState<WorkspaceSearchPanel> createState() =>
      _WorkspaceSearchPanelState();
}

class _WorkspaceSearchPanelState extends ConsumerState<WorkspaceSearchPanel> {
  late final TextEditingController _queryController;
  late final TextEditingController _replacementController;
  late final TextEditingController _includeController;
  late final TextEditingController _excludeController;
  bool _replaceVisible = false;
  bool _detailsVisible = false;
  String? _initializedOptionalSectionsWorkspaceId;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _replacementController = TextEditingController();
    _includeController = TextEditingController();
    _excludeController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _replacementController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = workspaceSearchControllerProvider(widget.workspace.id);
    final state = ref.watch(provider);
    _syncController(_queryController, state.query);
    _syncController(_replacementController, state.replacement);
    _syncController(_includeController, state.includePattern);
    _syncController(_excludeController, state.excludePattern);
    _initializeOptionalSections(state);
    final controller = ref.read(provider.notifier);
    final collapsibleNodeKeys = workspaceSearchCollapsibleNodeKeys(
      state.result,
      viewAsTree: state.viewAsTree,
    );
    final allResultsCollapsed =
        collapsibleNodeKeys.isNotEmpty &&
        collapsibleNodeKeys.every(state.collapsedResultNodeKeys.contains);
    final rows = _SearchRows.from(
      state.result,
      collapsedResultNodeKeys: state.collapsedResultNodeKeys,
      viewAsTree: state.viewAsTree,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SearchToolbar(
          state: state,
          allResultsCollapsed: allResultsCollapsed,
          onRefresh: () =>
              unawaited(controller.searchNow(widget.workspace.path)),
          onClear: controller.clearSearchResults,
          onToggleViewAsTree: controller.toggleViewAsTree,
          onToggleAllResultsCollapsed: controller.toggleAllResultsCollapsed,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space4,
            AleraTokens.space8,
            AleraTokens.space8,
            AleraTokens.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _WorkspaceSearchInputs(
                queryController: _queryController,
                replacementController: _replacementController,
                includeController: _includeController,
                excludeController: _excludeController,
                state: state,
                replaceVisible: _replaceVisible,
                detailsVisible: _detailsVisible,
                canReplaceAll: _canReplaceAll(state),
                onToggleReplace: _toggleReplacement,
                onToggleDetails: _toggleDetails,
                onQueryChanged: (value) =>
                    controller.setQuery(widget.workspace.path, value),
                onQuerySubmitted: (_) =>
                    unawaited(controller.searchNow(widget.workspace.path)),
                onReplacementChanged: (value) =>
                    controller.setReplacement(widget.workspace.path, value),
                onIncludeChanged: (value) =>
                    controller.setIncludePattern(widget.workspace.path, value),
                onExcludeChanged: (value) =>
                    controller.setExcludePattern(widget.workspace.path, value),
                onToggleCaseSensitive: () =>
                    controller.toggleCaseSensitive(widget.workspace.path),
                onToggleWholeWord: () =>
                    controller.toggleWholeWord(widget.workspace.path),
                onToggleUseRegex: () =>
                    controller.toggleUseRegex(widget.workspace.path),
                onTogglePreserveCase: () =>
                    controller.togglePreserveCase(widget.workspace.path),
                onReplaceAll: () => unawaited(_replace(const <String>[])),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        _SearchSummary(state: state),
        if (state.error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space8,
              0,
              AleraTokens.space8,
              AleraTokens.space8,
            ),
            child: Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
            ),
          ),
        Expanded(
          child: rows.items.isEmpty
              ? _SearchEmptyState(state: state)
              : ListView.builder(
                  itemCount: rows.items.length,
                  itemBuilder: (context, index) {
                    final item = rows.items[index];
                    return switch (item) {
                      _SearchDirectoryRow(
                        :final name,
                        :final path,
                        :final depth,
                        :final matchCount,
                      ) =>
                        _SearchDirectoryResultRow(
                          name: name,
                          matchCount: matchCount,
                          depth: depth,
                          collapsed: state.collapsedResultNodeKeys.contains(
                            workspaceSearchDirectoryNodeKey(path),
                          ),
                          onToggleCollapsed: () =>
                              controller.toggleResultNodeCollapsed(
                                workspaceSearchDirectoryNodeKey(path),
                              ),
                        ),
                      _SearchFileRow(:final file, :final depth) =>
                        _SearchFileResultRow(
                          file: file,
                          collapsed: state.collapsedResultNodeKeys.contains(
                            workspaceSearchFileNodeKey(file.relativePath),
                          ),
                          depth: depth,
                          showDirectory: !state.viewAsTree,
                          replacing: state.replacing,
                          onToggleCollapsed: () =>
                              controller.toggleResultNodeCollapsed(
                                workspaceSearchFileNodeKey(file.relativePath),
                              ),
                          onReplaceFile:
                              _replaceVisible &&
                                  workspaceSearchCanReplaceFile(state)
                              ? () => unawaited(
                                  _replace(
                                    file.matches.map((match) => match.id),
                                  ),
                                )
                              : null,
                        ),
                      _SearchMatchRow(
                        :final file,
                        :final match,
                        :final depth,
                      ) =>
                        _SearchMatchResultRow(
                          file: file,
                          match: match,
                          depth: depth,
                          replacing: state.replacing,
                          showReplacementPreview: _replaceVisible,
                          onOpen: () => widget.onOpenMatch(
                            WorkspaceSearchMatchTarget(
                              relativePath: file.relativePath,
                              line: match.line,
                              column: match.column,
                              matchLength: match.matchLength,
                            ),
                          ),
                          onReplace: _replaceVisible && _canReplace(state)
                              ? () => unawaited(_replace(<String>[match.id]))
                              : null,
                        ),
                    };
                  },
                ),
        ),
      ],
    );
  }

  bool _canReplace(WorkspaceSearchState state) {
    return state.hasQuery &&
        !state.loading &&
        !state.replacing &&
        (state.result?.totalMatches ?? 0) > 0;
  }

  bool _canReplaceAll(WorkspaceSearchState state) {
    return _canReplace(state) && state.result?.truncated != true;
  }

  Future<void> _replace(Iterable<String> matchIds) async {
    final provider = workspaceSearchControllerProvider(widget.workspace.id);
    try {
      final result = await ref
          .read(provider.notifier)
          .replaceMatches(
            workspacePath: widget.workspace.path,
            matchIds: matchIds,
            editorSessions: ref.read(editorSessionRegistryProvider),
          );
      if (!mounted) {
        return;
      }
      final conflictMessage = workspaceSearchReplaceConflictMessage(result);
      if (conflictMessage != null) {
        AleraToast.show(
          context,
          message: conflictMessage,
          tone: AleraToastTone.error,
        );
        return;
      }
      AleraToast.show(
        context,
        message:
            'Replaced ${result.matchesReplaced} ${result.matchesReplaced == 1 ? 'match' : 'matches'}.',
      );
    } catch (_) {
      final message = ref.read(provider).error;
      if (!mounted || message == null) {
        return;
      }
      AleraToast.show(context, message: message, tone: AleraToastTone.error);
    }
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _initializeOptionalSections(WorkspaceSearchState state) {
    if (_initializedOptionalSectionsWorkspaceId == widget.workspace.id) {
      return;
    }
    _replaceVisible = state.replacement.isNotEmpty;
    _detailsVisible =
        state.includePattern.isNotEmpty || state.excludePattern.isNotEmpty;
    _initializedOptionalSectionsWorkspaceId = widget.workspace.id;
  }

  void _toggleReplacement() {
    setState(() => _replaceVisible = !_replaceVisible);
  }

  void _toggleDetails() {
    setState(() => _detailsVisible = !_detailsVisible);
  }
}
