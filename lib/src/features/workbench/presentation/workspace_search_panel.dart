import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_search_panel_feedback.dart';
part 'workspace_search_panel_results.dart';
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
    final controller = ref.read(provider.notifier);
    final rows = _SearchRows.from(
      state.result,
      collapsedFilePaths: state.collapsedFilePaths,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AleraTextField(
                controller: _queryController,
                dense: true,
                autofocus: true,
                prefixIcon: Icons.search,
                hintText: 'Search',
                onChanged: (value) =>
                    controller.setQuery(widget.workspace.path, value),
                onSubmitted: (_) =>
                    unawaited(controller.searchNow(widget.workspace.path)),
              ),
              const SizedBox(height: AleraTokens.space6),
              AleraTextField(
                controller: _replacementController,
                dense: true,
                prefixIcon: Icons.find_replace,
                hintText: 'Replace',
                onChanged: (value) =>
                    controller.setReplacement(widget.workspace.path, value),
              ),
              const SizedBox(height: AleraTokens.space6),
              Row(
                children: <Widget>[
                  _SearchToggleButton(
                    tooltip: 'Match case',
                    icon: Icons.text_fields,
                    active: state.caseSensitive,
                    onPressed: () =>
                        controller.toggleCaseSensitive(widget.workspace.path),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  _SearchToggleButton(
                    tooltip: 'Match whole word',
                    icon: Icons.title,
                    active: state.wholeWord,
                    onPressed: () =>
                        controller.toggleWholeWord(widget.workspace.path),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  _SearchToggleButton(
                    tooltip: 'Use regular expression',
                    icon: Icons.code,
                    active: state.useRegex,
                    onPressed: () =>
                        controller.toggleUseRegex(widget.workspace.path),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  _SearchToggleButton(
                    tooltip: 'Preserve case',
                    icon: Icons.swap_horiz,
                    active: state.preserveCase,
                    onPressed: () =>
                        controller.togglePreserveCase(widget.workspace.path),
                  ),
                  const Spacer(),
                  AleraIconButton(
                    tooltip: 'Replace all',
                    icon: Icons.done_all,
                    onPressed: _canReplaceAll(state)
                        ? () => unawaited(_replace(const <String>[]))
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space6),
              AleraTextField(
                controller: _includeController,
                dense: true,
                prefixIcon: Icons.filter_alt_outlined,
                hintText: 'Files to include',
                onChanged: (value) =>
                    controller.setIncludePattern(widget.workspace.path, value),
              ),
              const SizedBox(height: AleraTokens.space6),
              AleraTextField(
                controller: _excludeController,
                dense: true,
                prefixIcon: Icons.filter_alt_off_outlined,
                hintText: 'Files to exclude',
                onChanged: (value) =>
                    controller.setExcludePattern(widget.workspace.path, value),
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
                      _SearchFileRow(:final file) => _SearchFileResultRow(
                        file: file,
                        collapsed: state.collapsedFilePaths.contains(
                          file.relativePath,
                        ),
                        replacing: state.replacing,
                        onToggleCollapsed: () =>
                            controller.toggleFileCollapsed(file.relativePath),
                        onReplaceFile: workspaceSearchCanReplaceFile(state)
                            ? () => unawaited(
                                _replace(file.matches.map((match) => match.id)),
                              )
                            : null,
                      ),
                      _SearchMatchRow(:final file, :final match) =>
                        _SearchMatchResultRow(
                          file: file,
                          match: match,
                          replacing: state.replacing,
                          onOpen: () => widget.onOpenMatch(
                            WorkspaceSearchMatchTarget(
                              relativePath: file.relativePath,
                              line: match.line,
                              column: match.column,
                              matchLength: match.matchLength,
                            ),
                          ),
                          onReplace: _canReplace(state)
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
}
