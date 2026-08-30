import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _quickOpenResultLimit = 50;

class QuickOpenDialog extends ConsumerStatefulWidget {
  const QuickOpenDialog({super.key});

  @override
  ConsumerState<QuickOpenDialog> createState() => _QuickOpenDialogState();
}

class _QuickOpenDialogState extends ConsumerState<QuickOpenDialog> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  late final WorkspaceFileService _workspaceFiles;

  String? _workspaceId;
  native.WorkspaceQuickOpenSession? _session;
  List<native.WorkspaceQuickOpenMatch> _matches =
      const <native.WorkspaceQuickOpenMatch>[];
  bool _loading = true;
  Object? _loadError;
  int _selectedIndex = 0;
  int _workspaceGeneration = 0;
  int _searchGeneration = 0;
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final ScrollController _resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    ref.listenManual<String?>(
      workbenchControllerProvider.select((state) => state.activeWorkspaceId),
      (previous, next) {
        if (previous != next) {
          unawaited(_reloadWorkspace());
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    final session = _session;
    _session = null;
    _workspaceGeneration++;
    _searchGeneration++;
    if (session != null) {
      unawaited(_stopSession(session));
    }
    _queryController.dispose();
    _queryFocusNode.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadWorkspace() async {
    final workspace = ref.read(workbenchControllerProvider).activeWorkspace;
    final workspaceId = workspace?.id;
    final generation = ++_workspaceGeneration;
    ++_searchGeneration;
    final previousSession = _session;
    _session = null;
    if (previousSession != null) {
      unawaited(_stopSession(previousSession));
    }
    final workspaceChanged = _workspaceId != workspaceId;
    _workspaceId = workspaceId;
    if (workspaceChanged) {
      _queryController.clear();
    }
    if (!mounted) {
      return;
    }
    _resetResultsScroll();
    setState(() {
      _matches = const <native.WorkspaceQuickOpenMatch>[];
      _selectedIndex = 0;
      _loadError = null;
      _loading = workspace != null;
      _rowKeys.clear();
    });
    if (workspace == null) {
      if (mounted && generation == _workspaceGeneration) {
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final session = await _workspaceFiles.startQuickOpenSession(
        workspacePath: workspace.path,
      );
      if (!mounted || generation != _workspaceGeneration) {
        unawaited(_stopSession(session));
        return;
      }
      _session = session;
      final searchGeneration = ++_searchGeneration;
      await _searchSession(
        session: session,
        workspaceGeneration: generation,
        searchGeneration: searchGeneration,
        query: _queryController.text,
      );
    } catch (error) {
      if (!mounted || generation != _workspaceGeneration) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _searchSession({
    required native.WorkspaceQuickOpenSession session,
    required int workspaceGeneration,
    required int searchGeneration,
    required String query,
  }) async {
    try {
      final matches = await _workspaceFiles.searchQuickOpenSession(
        session: session,
        query: query,
        limit: _quickOpenResultLimit,
      );
      if (!_isCurrentSearch(session, workspaceGeneration, searchGeneration)) {
        return;
      }
      setState(() {
        _matches = matches;
        _selectedIndex = 0;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!_isCurrentSearch(session, workspaceGeneration, searchGeneration)) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  bool _isCurrentSearch(
    native.WorkspaceQuickOpenSession session,
    int workspaceGeneration,
    int searchGeneration,
  ) {
    return mounted &&
        workspaceGeneration == _workspaceGeneration &&
        searchGeneration == _searchGeneration &&
        identical(_session, session);
  }

  void _updateQuery(String query) {
    final session = _session;
    final workspaceGeneration = _workspaceGeneration;
    final searchGeneration = ++_searchGeneration;
    _resetResultsScroll();
    setState(() {
      _matches = const <native.WorkspaceQuickOpenMatch>[];
      _selectedIndex = 0;
      if (session != null) {
        _loading = true;
      }
    });
    if (session != null) {
      unawaited(
        _searchSession(
          session: session,
          workspaceGeneration: workspaceGeneration,
          searchGeneration: searchGeneration,
          query: query,
        ),
      );
    }
  }

  void _resetResultsScroll() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
  }

  Future<void> _stopSession(native.WorkspaceQuickOpenSession session) async {
    try {
      await _workspaceFiles.stopQuickOpenSession(session: session);
    } catch (_) {
      // Session cleanup is best effort during stale requests and disposal.
    }
  }

  void _moveSelection(int delta) {
    if (_matches.isEmpty) {
      return;
    }
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _matches.length;
      if (_selectedIndex < 0) {
        _selectedIndex += _matches.length;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _matches.isEmpty) {
        return;
      }
      final rowContext =
          _rowKeys[_matches[_selectedIndex].relativePath]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: AleraTokens.durationFast,
        );
      } else if (_resultsScrollController.hasClients) {
        final position = _resultsScrollController.position;
        final itemExtent = AleraTokens.space32;
        final itemTop = _selectedIndex * itemExtent;
        final itemBottom = itemTop + itemExtent;
        final visibleTop = position.pixels;
        final visibleBottom = visibleTop + position.viewportDimension;
        final target = itemTop < visibleTop
            ? itemTop
            : itemBottom > visibleBottom
            ? itemBottom - position.viewportDimension
            : position.pixels;
        if (target != position.pixels) {
          _resultsScrollController.animateTo(
            target.clamp(0.0, position.maxScrollExtent),
            duration: AleraTokens.durationFast,
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _openSelected() {
    final workspace = ref.read(workbenchControllerProvider).activeWorkspace;
    if (workspace == null || _matches.isEmpty) {
      return;
    }
    final relativePath = _matches[_selectedIndex].relativePath;
    Navigator.of(
      context,
    ).pop((workspace: workspace, relativePath: relativePath));
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _openSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspace = ref.watch(
      workbenchControllerProvider.select((state) => state.activeWorkspace),
    );
    return Focus(
      onKeyEvent: _handleKey,
      child: AleraDialog(
        maxWidth: AleraTokens.dialogWideWidth,
        maxHeight: AleraTokens.dialogMaxHeight,
        child: SizedBox(
          width: AleraTokens.dialogWideWidth,
          height: AleraTokens.dialogMaxHeight,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('Quick Open', style: theme.textTheme.titleMedium),
                    const SizedBox(width: AleraTokens.space12),
                    if (workspace != null)
                      Expanded(
                        child: Text(
                          workspace.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space16),
                AleraTextField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  autofocus: true,
                  hintText: 'Search workspace files',
                  prefixIcon: AleraIcons.search,
                  onChanged: _updateQuery,
                  onSubmitted: (_) => _openSelected(),
                ),
                const SizedBox(height: AleraTokens.space12),
                Expanded(child: _buildResults(theme)),
                const Divider(height: AleraTokens.space20),
                Text(
                  'Use Up and Down to navigate, Enter to open, or Escape to close.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: AleraTokens.space12),
            Text('Loading workspace files...'),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(AleraIcons.error, color: AleraTokens.error),
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Could not load workspace files.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                _loadError.toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_matches.isEmpty) {
      final query = _queryController.text.trim();
      return Center(
        child: Text(
          query.isEmpty
              ? 'No files are available in this workspace.'
              : 'No files match "$query".',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey<String>('quick-open-results'),
      controller: _resultsScrollController,
      itemExtent: AleraTokens.space32,
      padding: EdgeInsets.zero,
      itemCount: _matches.length,
      itemBuilder: (context, index) {
        final match = _matches[index];
        final selected = index == _selectedIndex;
        final rowKey = _rowKeys.putIfAbsent(
          match.relativePath,
          () => GlobalKey(),
        );
        return Material(
          key: rowKey,
          color: selected ? AleraTokens.accentSubtle : null,
          child: InkWell(
            onTap: () {
              setState(() => _selectedIndex = index);
              _openSelected();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  AleraFileIcon(
                    pathOrName: match.relativePath,
                    kind: AleraFileIconKind.file,
                    size: AleraTokens.space16,
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(
                    child: Text(
                      match.relativePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
