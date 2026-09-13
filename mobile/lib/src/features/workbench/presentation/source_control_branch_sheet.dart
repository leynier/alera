import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_actions_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_branches.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class _BranchChoice {
  const _BranchChoice();
}

class const _SwitchBranch(this.branch) extends _BranchChoice {
  final String branch;
}

class const _CreateBranch(this.branch) extends _BranchChoice {
  final String branch;
}

/// Lets the user switch to a branch or create one from HEAD, then runs it.
Future<void> showSourceControlBranchSheet(
  SourceControlCommandRunner runner,
  String? currentBranch,
) async {
  final choice = await showModalBottomSheet<_BranchChoice>(
    context: runner.context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _BranchSheet(
            hostId: runner.hostId,
            workspaceId: runner.workspaceId,
            currentBranch: currentBranch,
          ),
        ),
      ),
    ),
  );
  if (!runner.context.mounted) {
    return;
  }
  switch (choice) {
    case _SwitchBranch(:final branch) when branch != currentBranch:
      await runner.write(
        MobileGitWrite.checkout(branch),
        successMessage: 'Switched to $branch',
      );
    case _CreateBranch(:final branch):
      await runner.write(
        MobileGitWrite.createBranch(branch),
        successMessage: 'Created $branch',
      );
    case _:
      return;
  }
}

class const _BranchSheet({
  required final String hostId,
  required final String workspaceId,
  required final String? currentBranch,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends ConsumerState<_BranchSheet> {
  final TextEditingController _name = TextEditingController();
  String _query = '';
  bool _creating = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submitCreate(List<String> branches) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Branch name is required');
      return;
    }
    if (branches.contains(name)) {
      setState(() => _nameError = 'A branch named "$name" already exists');
      return;
    }
    Navigator.of(context).pop(_CreateBranch(name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branches = ref.watch(
      sourceControlBranchesProvider(widget.hostId, widget.workspaceId),
    );
    final names = branches.value?.branches ?? const <String>[];
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            0,
            AleraTokens.space16,
            AleraTokens.space8,
          ),
          child: Text(
            _creating ? 'Create Branch' : 'Switch Branch',
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (_creating)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                AleraTextField(
                  controller: _name,
                  autofocus: true,
                  labelText: 'Branch Name',
                  hintText: 'e.g. feature/login',
                  errorText: _nameError,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                  onSubmitted: (_) => _submitCreate(names),
                ),
                const SizedBox(height: AleraTokens.space12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _creating = false;
                          _nameError = null;
                        }),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: FilledButton(
                        onPressed: branches.hasValue
                            ? () => _submitCreate(names)
                            : null,
                        child: const Text('Create'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space16),
              ],
            ),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
            ),
            child: AleraSearchField(
              hintText: 'Search branches',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ListTile(
            minTileHeight: AleraTokens.minTapTarget,
            leading: const Icon(AleraIcons.add),
            title: const Text('Create Branch'),
            onTap: () => setState(() => _creating = true),
          ),
          const Divider(height: 1),
          Flexible(child: _branchList(branches, names)),
        ],
      ],
    );
  }

  Widget _branchList(
    AsyncValue<MobileGitBranches> branches,
    List<String> names,
  ) {
    if (branches case AsyncError(:final error)) {
      return AleraEmptyState(
        icon: AleraIcons.gitBranch,
        message: sourceControlErrorMessage(error),
      );
    }
    if (!branches.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(AleraTokens.space24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final query = _query.trim().toLowerCase();
    final visible = <String>[
      for (final name in names)
        if (query.isEmpty || name.toLowerCase().contains(query)) name,
    ];
    if (visible.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.gitBranch,
        message: 'No branches match.',
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final name = visible[index];
        final isCurrent = name == widget.currentBranch;
        return ListTile(
          minTileHeight: AleraTokens.minTapTarget,
          leading: const Icon(AleraIcons.gitBranch),
          title: Text(name, maxLines: 1, overflow: .ellipsis),
          trailing: isCurrent ? const Icon(AleraIcons.check) : null,
          onTap: () => Navigator.of(context).pop(_SwitchBranch(name)),
        );
      },
    );
  }
}
