part of 'mobile_codex_chat_screen.dart';

class _MobileResumeSelection {
  const _MobileResumeSelection(this.thread);

  final MobileCodexThreadSummary thread;
}

class _MobileCodexResumePicker extends StatefulWidget {
  const _MobileCodexResumePicker({
    required this.workspaceId,
    required this.loadPage,
  });

  final String workspaceId;
  final Future<MobileCodexThreadPage> Function({
    String? workspaceId,
    String? searchTerm,
    String? cursor,
  })
  loadPage;

  @override
  State<_MobileCodexResumePicker> createState() =>
      _MobileCodexResumePickerState();
}

class _MobileCodexResumePickerState extends State<_MobileCodexResumePicker> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchTimer;
  MobileCodexThreadPage _page = const MobileCodexThreadPage();
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
      _loading = cursor == null;
      _loadingMore = cursor != null;
      _error = null;
    });
    try {
      final next = await widget.loadPage(
        workspaceId: _workspaceOnly ? widget.workspaceId : null,
        searchTerm: _search.text.trim().isEmpty ? null : _search.text.trim(),
        cursor: cursor,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _page = cursor == null ? next : _page.append(next);
        _loading = false;
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Could not load Codex threads for resume.',
        error,
        stackTrace,
      );
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
    _searchTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Resume Codex Thread',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.space8),
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
            const SizedBox(height: AleraTokens.space8),
            Expanded(child: _results(context)),
          ],
        ),
      ),
    ),
  );

  Widget _results(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Could not load Codex threads. $_error'));
    }
    if (_page.items.isEmpty && _page.nextCursor == null) {
      return const Center(child: Text('No Codex Threads Found'));
    }
    return ListView.separated(
      itemCount: _page.items.length + (_page.nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: AleraTokens.space2),
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
          key: ValueKey<String>('mobile-codex-resume-${thread.id}'),
          title: Text(thread.title),
          subtitle: Text(
            <String>[
              if (thread.workspaceName case final name? when name.isNotEmpty)
                name,
              if (thread.cwd case final cwd? when cwd.isNotEmpty) cwd,
              if (thread.isBound) 'Already Open',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () =>
              Navigator.of(context).pop(_MobileResumeSelection(thread)),
        );
      },
    );
  }
}
