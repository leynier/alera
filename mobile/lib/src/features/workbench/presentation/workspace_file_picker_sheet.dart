import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final Logger _logger = Logger('WorkspaceFilePickerSheet');

/// Quick Open over a workspace, as a searchable sheet that pops the chosen
/// relative path. Shared by the Codex chat composer and the terminal.
///
/// The session lifecycle arrives as callbacks rather than a client, so the
/// caller decides whether it goes through a Codex controller or straight to the
/// runtime client.
class const WorkspaceFilePickerSheet({
  super.key,
  required final Future<MobileWorkspaceQuickOpenSession> Function() start,
  required final Future<List<MobileWorkspaceQuickOpenMatch>> Function(
    MobileWorkspaceQuickOpenSession session,
    String query,
  )
  search,
  required final Future<void> Function(MobileWorkspaceQuickOpenSession session)
  stop,
}) extends StatefulWidget {
  @override
  State<WorkspaceFilePickerSheet> createState() =>
      _WorkspaceFilePickerSheetState();
}

class _WorkspaceFilePickerSheetState extends State<WorkspaceFilePickerSheet> {
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
      unawaited(_stop(session));
    }
    super.dispose();
  }

  Future<void> _stop(MobileWorkspaceQuickOpenSession session) async {
    try {
      await widget.stop(session);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not stop a mobile Quick Open session.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _start() async {
    try {
      final session = await widget.start();
      if (!mounted) {
        await _stop(session);
        return;
      }
      _session = session;
      await _search();
    } on Object catch (error, stackTrace) {
      _logger.warning('Quick Open indexing failed.', error, stackTrace);
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
      final matches = await widget.search(session, _query.text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _matches = matches;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      _logger.warning('Quick Open search failed.', error, stackTrace);
      if (mounted && generation == _generation) {
        if (identical(_session, session)) {
          _session = null;
          unawaited(_stop(session));
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
                      mainAxisSize: .min,
                      children: <Widget>[
                        const Text(
                          'Workspace files could not be loaded.',
                          textAlign: .center,
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
                      leading: Icon(workspaceFileIcon(match.relativePath)),
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

/// Shows [WorkspaceFilePickerSheet] and resolves with the chosen relative path.
Future<String?> showWorkspaceFilePickerSheet(
  BuildContext context, {
  required Future<MobileWorkspaceQuickOpenSession> Function() start,
  required Future<List<MobileWorkspaceQuickOpenMatch>> Function(
    MobileWorkspaceQuickOpenSession session,
    String query,
  )
  search,
  required Future<void> Function(MobileWorkspaceQuickOpenSession session) stop,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.78,
      child: WorkspaceFilePickerSheet(start: start, search: search, stop: stop),
    ),
  );
}

String workspaceFileBaseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

IconData workspaceFileIcon(String path) =>
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
