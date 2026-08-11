part of 'mobile_codex_chat_screen.dart';

Future<void> _stopMobileWorkspaceQuickOpen(
  MobileCodexController controller,
  MobileWorkspaceQuickOpenSession session,
) async {
  try {
    await controller.stopWorkspaceQuickOpen(session);
  } on Object catch (error, stackTrace) {
    _MobileCodexChatScreenState._logger.warning(
      'Could not stop a mobile Quick Open session.',
      error,
      stackTrace,
    );
  }
}

class _MobileWorkspaceFilePicker extends StatefulWidget {
  const _MobileWorkspaceFilePicker({
    required this.controller,
    required this.workspaceId,
    required this.cwd,
  });

  final MobileCodexController controller;
  final String workspaceId;
  final String? cwd;

  @override
  State<_MobileWorkspaceFilePicker> createState() =>
      _MobileWorkspaceFilePickerState();
}

class _MobileWorkspaceFilePickerState
    extends State<_MobileWorkspaceFilePicker> {
  final TextEditingController _query = TextEditingController();
  MobileWorkspaceQuickOpenSession? _session;
  List<MobileWorkspaceQuickOpenMatch> _matches =
      const <MobileWorkspaceQuickOpenMatch>[];
  Timer? _debounce;
  Object? _error;
  var _loading = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_scheduleSearch);
    unawaited(_start());
  }

  @override
  void dispose() {
    _query.removeListener(_scheduleSearch);
    _query.dispose();
    _debounce?.cancel();
    final session = _session;
    if (session != null) {
      unawaited(_stopMobileWorkspaceQuickOpen(widget.controller, session));
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final session = await widget.controller.startWorkspaceQuickOpen(
        widget.workspaceId,
        cwd: widget.cwd,
      );
      if (!mounted) {
        await _stopMobileWorkspaceQuickOpen(widget.controller, session);
        return;
      }
      _session = session;
      await _search();
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Quick Open indexing failed.',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_search());
    });
  }

  Future<void> _search() async {
    final session = _session;
    if (session == null) return;
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final matches = await widget.controller.searchWorkspaceQuickOpen(
        session,
        _query.text,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _matches = matches;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Quick Open search failed.',
        error,
        stackTrace,
      );
      if (mounted && generation == _generation) {
        if (identical(_session, session)) {
          _session = null;
          unawaited(_stopMobileWorkspaceQuickOpen(widget.controller, session));
        }
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _retry() {
    if (_session == null) {
      setState(() {
        _error = null;
        _loading = true;
      });
      unawaited(_start());
      return;
    }
    unawaited(_search());
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: <Widget>[
        Padding(
          padding: AleraTokens.contentPadding,
          child: TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Workspace File',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (_loading)
          const LinearProgressIndicator(minHeight: AleraTokens.space2),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: AleraTokens.contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'Workspace files could not be loaded.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AleraTokens.space12),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _matches.length,
                  itemBuilder: (context, index) {
                    final match = _matches[index];
                    return ListTile(
                      minTileHeight: AleraTokens.minTapTarget,
                      leading: Icon(_mobileFileIcon(match.relativePath)),
                      title: Text(match.relativePath),
                      onTap: () =>
                          Navigator.of(context).pop(match.relativePath),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

String _mobileBaseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

IconData _mobileFileIcon(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.dart' => Icons.flutter_dash,
      '.rs' => Icons.settings_outlined,
      '.md' || '.mdx' => Icons.description_outlined,
      '.json' || '.yaml' || '.yml' || '.toml' => Icons.data_object,
      '.png' || '.jpg' || '.jpeg' || '.gif' || '.webp' => Icons.image_outlined,
      '.sql' => Icons.storage_outlined,
      '.sh' || '.ps1' || '.bat' => Icons.terminal,
      _ => Icons.insert_drive_file_outlined,
    };
