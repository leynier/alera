import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_text_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostId = widget.hostId;
    final workspaceId = widget.workspaceId;
    final state = ref.watch(
      workspaceTextSearchControllerProvider(hostId, workspaceId),
    );
    final notifier = ref.read(
      workspaceTextSearchControllerProvider(hostId, workspaceId).notifier,
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            children: <Widget>[
              AleraSearchField(
                controller: _query,
                hintText: 'Search',
                autofocus: true,
                onChanged: notifier.setQuery,
              ),
              const SizedBox(height: AleraTokens.space8),
              Row(
                children: <Widget>[
                  _Toggle(
                    label: 'Aa',
                    tooltip: 'Match Case',
                    active: state.caseSensitive,
                    onPressed: notifier.toggleCaseSensitive,
                  ),
                  _Toggle(
                    label: 'ab',
                    tooltip: 'Match Whole Word',
                    active: state.wholeWord,
                    onPressed: notifier.toggleWholeWord,
                  ),
                  _Toggle(
                    label: '.*',
                    tooltip: 'Use Regular Expression',
                    active: state.useRegex,
                    onPressed: notifier.toggleUseRegex,
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space8),
              AleraTextField(
                hintText: 'Include files',
                onChanged: notifier.setIncludePattern,
              ),
              const SizedBox(height: AleraTokens.space8),
              AleraTextField(
                hintText: 'Exclude files',
                onChanged: notifier.setExcludePattern,
              ),
            ],
          ),
        ),
        if (state.searching)
          const LinearProgressIndicator(minHeight: AleraTokens.space2),
        Expanded(
          child: _Results(
            hostId: hostId,
            workspaceId: workspaceId,
            state: state,
          ),
        ),
      ],
    );
  }
}

class const _Toggle({
  required final String label,
  required final String tooltip,
  required final bool active,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: Tooltip(
        message: tooltip,
        child: FilterChip(
          label: Text(label),
          selected: active,
          onSelected: (_) => onPressed(),
        ),
      ),
    );
  }
}

class const _Results({
  required final String hostId,
  required final String workspaceId,
  required final WorkspaceTextSearchState state,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (state.error != null) {
      return AleraEmptyState(
        icon: AleraIcons.search,
        message: state.error.toString(),
      );
    }
    if (state.query.trim().isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.search,
        title: 'Search',
        message: 'Type to search the workspace.',
      );
    }
    final result = state.result;
    if (result == null || result.files.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.search,
        title: 'No matches',
        message: 'Nothing in this workspace matched the query.',
      );
    }
    return ListView.builder(
      itemCount: result.files.length,
      itemBuilder: (context, index) {
        final file = result.files[index];
        return ExpansionTile(
          title: Text(file.relativePath),
          subtitle: Text(
            '${file.matches.length} ${file.matches.length == 1 ? 'match' : 'matches'}',
          ),
          children: <Widget>[
            for (final match in file.matches)
              ListTile(
                minTileHeight: AleraTokens.minTapTarget,
                title: Text(
                  match.lineContent,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle,
                ),
                subtitle: Text('Line ${match.line}'),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkspaceFileViewerScreen(
                      hostId: hostId,
                      workspaceId: workspaceId,
                      relativePath: file.relativePath,
                      highlightLine: match.line,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
