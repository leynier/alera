import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/mcp_access/application/mcp_access_providers.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_error_message.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_access_control_group.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_connected_apps_group.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_runtime_name_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings pane for remote MCP Control: access level, runtime name, endpoint
/// and connected apps. Wires the providers into presentational groups.
class const McpAccessSettingsPane({
  super.key,
  final Map<String, GlobalKey> groupKeys = const <String, GlobalKey>{},
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<McpAccessSettingsPane> createState() =>
      _McpAccessSettingsPaneState();
}

class _McpAccessSettingsPaneState extends ConsumerState<McpAccessSettingsPane> {
  final TextEditingController _nameController = TextEditingController();
  String? _seededName;
  bool _applyingAccess = false;
  bool _renaming = false;
  bool _endpointCopied = false;
  String? _accessError;
  String? _renameError;
  String? _revokeError;
  final Set<String> _revokingIds = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Follows the runtime's name until the user edits the field, so a rename
  // from the CLI shows up without overwriting a name being typed.
  void _seedName(McpAccessSettings settings) {
    final name = settings.effectiveRuntimeName;
    if (_seededName == name) {
      return;
    }
    if (_seededName == null || _nameController.text == _seededName) {
      _nameController.text = name;
    }
    _seededName = name;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(mcpAccessSettingsControllerProvider);
    return settingsAsync.when(
      loading: () => const AleraEmptyState(
        loading: true,
        message: 'Loading MCP settings…',
      ),
      error: (error, _) => AleraEmptyState(
        icon: AleraIcons.mcp,
        title: 'MCP Control unavailable',
        message: mcpAccessErrorMessage(error),
      ),
      data: (settings) {
        if (settings == null) {
          return const AleraEmptyState(
            icon: AleraIcons.mcp,
            title: 'MCP Control unavailable',
            message: 'Update the Alera runtime to use MCP Control.',
          );
        }
        _seedName(settings);
        return Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            KeyedSubtree(
              key: widget.groupKeys['control'],
              child: McpAccessControlGroup(
                settings: settings,
                applying: _applyingAccess,
                error: _accessError,
                endpointCopied: _endpointCopied,
                onAccessSelected: _setAccess,
                onCopyEndpoint: _copyEndpoint,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            KeyedSubtree(
              key: widget.groupKeys['runtime'],
              child: McpRuntimeNameGroup(
                settings: settings,
                controller: _nameController,
                saving: _renaming,
                error: _renameError,
                onChanged: (_) => setState(() => _renameError = null),
                onRename: _rename,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            KeyedSubtree(
              key: widget.groupKeys['apps'],
              child: McpConnectedAppsGroup(
                view: _appsView(settings),
                revokingIds: _revokingIds,
                error: _revokeError,
                onRefresh: _refreshGrants,
                onRevoke: _revoke,
              ),
            ),
          ],
        );
      },
    );
  }

  McpConnectedAppsView _appsView(McpAccessSettings settings) {
    if (!settings.accountConnected) {
      return const McpConnectedAppsSignedOut();
    }
    // `when` keeps the previous list on screen while a refresh is in flight.
    return ref
        .watch(mcpGrantsProvider)
        .when(
          data: McpConnectedAppsLoaded.new,
          error: (error, _) =>
              McpConnectedAppsFailed(mcpAccessErrorMessage(error)),
          loading: McpConnectedAppsLoading.new,
        );
  }

  Future<void> _setAccess(McpAccessLevel access) async {
    setState(() {
      _applyingAccess = true;
      _accessError = null;
    });
    try {
      await ref
          .read(mcpAccessSettingsControllerProvider.notifier)
          .setAccess(access);
      if (mounted) {
        setState(() => _applyingAccess = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _applyingAccess = false;
          _accessError = mcpAccessErrorMessage(error);
        });
      }
    }
  }

  Future<void> _rename() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() {
      _renaming = true;
      _renameError = null;
    });
    try {
      await ref.read(mcpAccessSettingsControllerProvider.notifier).rename(name);
      if (mounted) {
        setState(() => _renaming = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _renaming = false;
          _renameError = mcpAccessErrorMessage(error);
        });
      }
    }
  }

  Future<void> _copyEndpoint() async {
    await Clipboard.setData(const ClipboardData(text: aleraRemoteMcpEndpoint));
    if (mounted) {
      setState(() => _endpointCopied = true);
    }
  }

  void _refreshGrants() {
    setState(() => _revokeError = null);
    ref.invalidate(mcpGrantsProvider);
  }

  Future<void> _revoke(McpGrant grant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Revoke ${grant.clientName}',
        message:
            'The app loses access to every runtime it was granted and must be '
            'authorized again to reconnect.',
        confirmLabel: 'Revoke',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _revokingIds.add(grant.id);
      _revokeError = null;
    });
    try {
      await ref.read(mcpAccessRepositoryProvider).revokeGrant(grant.id);
      if (mounted) {
        ref.invalidate(mcpGrantsProvider);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _revokeError = mcpAccessErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _revokingIds.remove(grant.id));
      }
    }
  }
}
