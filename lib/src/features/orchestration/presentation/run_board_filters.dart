import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/features/orchestration/domain/run_board_location.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:flutter/material.dart';

class RunBoardFilters extends StatefulWidget {
  const RunBoardFilters({
    super.key,
    required this.location,
    required this.projects,
    required this.workspaces,
    required this.onSearch,
    required this.onProject,
    required this.onWorkspace,
    required this.onBucket,
    required this.onClear,
    this.counts,
  });
  final RunBoardLocation location;
  final List<AleraDropdownFieldEntry<String?>> projects;
  final List<AleraDropdownFieldEntry<String?>> workspaces;
  final RunBoardCounts? counts;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onProject;
  final ValueChanged<String?> onWorkspace;
  final ValueChanged<RunBoardBucket?> onBucket;
  final VoidCallback onClear;
  @override
  State<RunBoardFilters> createState() => _RunBoardFiltersState();
}

class _RunBoardFiltersState extends State<RunBoardFilters> {
  late final TextEditingController _search;
  Timer? _debounce;
  String? _searchError;
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.location.search);
  }

  @override
  void didUpdateWidget(RunBoardFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.search != widget.location.search &&
        _search.text != widget.location.search) {
      _debounce?.cancel();
      _search.text = widget.location.search;
      _searchError = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final tooLong = utf8.encode(value).length > 256;
    setState(
      () => _searchError = tooLong
          ? 'Search is limited to 256 UTF-8 bytes.'
          : null,
    );
    if (!tooLong) {
      _debounce = Timer(AleraTokens.durationSlow, () => widget.onSearch(value));
    }
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _searchError = null);
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AleraSearchField(
          controller: _search,
          hintText: 'Search Runs',
          onChanged: _changed,
        ),
        if (_searchError != null)
          Text(
            _searchError!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.warning),
          ),
        const SizedBox(height: AleraTokens.space12),
        AleraDropdownField<String?>(
          labelText: 'Project',
          value: widget.location.projectId,
          entries: widget.projects,
          filterable: true,
          filterHintText: 'Search Projects',
          onChanged: widget.onProject,
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraDropdownField<String?>(
          labelText: 'Workspace',
          value: widget.location.workspaceId,
          entries: widget.workspaces,
          filterable: true,
          filterHintText: 'Search Workspaces',
          onChanged: widget.onWorkspace,
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraDropdownField<RunBoardBucket?>(
          labelText: 'Status',
          value: widget.location.bucket,
          onChanged: widget.onBucket,
          entries: [
            const AleraDropdownFieldEntry(value: null, label: 'All Runs'),
            AleraDropdownFieldEntry(
              value: RunBoardBucket.attention,
              label:
                  'Attention${widget.counts == null ? '' : ' (${widget.counts!.attention})'}',
            ),
            AleraDropdownFieldEntry(
              value: RunBoardBucket.active,
              label:
                  'Active${widget.counts == null ? '' : ' (${widget.counts!.active})'}',
            ),
            AleraDropdownFieldEntry(
              value: RunBoardBucket.history,
              label:
                  'History${widget.counts == null ? '' : ' (${widget.counts!.history})'}',
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _clear,
            child: const Text('Clear Filters'),
          ),
        ),
      ],
    ),
  );
}
