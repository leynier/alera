part of 'codex_chat_surface.dart';

class const _CodexResumeSelection(final CodexThreadSummary thread);

class const _CodexResumePickerDialog({
  required final Workspace workspace,
  required final Future<CodexThreadPage> Function({
    String? workspaceId,
    String? searchTerm,
    String? cursor,
  })
  loadPage,
}) extends StatefulWidget {
  @override
  State<_CodexResumePickerDialog> createState() =>
      _CodexResumePickerDialogState();
}

class _CodexResumePickerDialogState extends State<_CodexResumePickerDialog> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchTimer;
  CodexThreadPage _page = const CodexThreadPage();
  bool _workspaceOnly = true;
  bool _loading = true;
  bool _loadingMore = false;
  int _loadGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? cursor}) async {
    final generation = ++_loadGeneration;
    setState(() {
      if (cursor == null) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final next = await widget.loadPage(
        workspaceId: _workspaceOnly ? widget.workspace.id : null,
        searchTerm: _search.text.trim().isEmpty ? null : _search.text.trim(),
        cursor: cursor,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _page = cursor == null ? next : _page.append(next);
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _scheduleSearch() {
    _searchTimer?.cancel();
    _searchTimer = Timer(AleraTokens.durationFast, () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AleraTokens.dialogWideWidth,
        maxWidth: AleraTokens.dialogWideWidth,
        maxHeight: AleraTokens.dialogMaxHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Resume Codex Thread',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment(value: true, label: Text('Workspace')),
                ButtonSegment(value: false, label: Text('All')),
              ],
              selected: <bool>{_workspaceOnly},
              onSelectionChanged: (value) {
                setState(() => _workspaceOnly = value.first);
                unawaited(_load());
              },
            ),
            const SizedBox(height: AleraTokens.space8),
            TextField(
              controller: _search,
              onChanged: (_) => _scheduleSearch(),
              decoration: const InputDecoration(
                labelText: 'Search Threads',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    ),
  );

  Widget _buildResults(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load Codex threads. $_error',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (_page.items.isEmpty && _page.nextCursor == null) {
      return const Center(child: Text('No Codex Threads Found'));
    }
    return ListView.separated(
      itemCount: _page.items.length + (_page.nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: AleraTokens.space4),
      itemBuilder: (context, index) {
        if (index == _page.items.length) {
          return TextButton(
            onPressed: _loadingMore
                ? null
                : () => _load(cursor: _page.nextCursor),
            child: Text(_loadingMore ? 'Loading...' : 'Load More'),
          );
        }
        final thread = _page.items[index];
        return ListTile(
          key: ValueKey<String>('codex-resume-thread-${thread.id}'),
          title: Text(thread.title),
          subtitle: Text(
            <String>[
              if (thread.workspaceName case final name? when name.isNotEmpty)
                name,
              if (thread.cwd case final cwd? when cwd.isNotEmpty) cwd,
              if (thread.isBound) 'Already Open',
            ].join(' / '),
            maxLines: 2,
            overflow: .ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(_CodexResumeSelection(thread)),
        );
      },
    );
  }
}
