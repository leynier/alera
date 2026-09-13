part of 'create_workspace_screen.dart';

extension _CreateWorkspaceLocation on _CreateWorkspaceScreenState {
  Widget _locationSelector({required String? projectId, bool enabled = true}) {
    final supportsWorktree = widget.projects.any(
      (project) => project.id == projectId && project.supportsLinkedWorkspaces,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (projectId != null) ...[
            _checkoutHostSelector(projectId, enabled),
            const SizedBox(height: AleraTokens.spaceMd),
          ],
          if (!widget.supportsSharedCheckoutWorkspaces)
            const Text(
              'Update Alera on this host to create tasks in the project folder.',
            ),
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment(
                value: true,
                label: const Text('Project Folder'),
                enabled: widget.supportsSharedCheckoutWorkspaces,
              ),
              ButtonSegment(
                value: false,
                label: const Text('New Worktree'),
                enabled: supportsWorktree,
              ),
            ],
            selected: <bool>{_useProjectCheckout},
            onSelectionChanged: enabled
                ? (selection) {
                    _update(() => _useProjectCheckout = selection.single);
                    if (projectId == null) return;
                    if (_fromPrompt) {
                      unawaited(
                        ref
                            .read(
                              promptWorkspaceControllerProvider(widget.hostId)
                                  .notifier,
                            )
                            .selectProject(
                              projectId,
                              defaultAgentProfileId:
                                  widget.defaultAgentProfileId,
                              loadBranches: !_useProjectCheckout,
                              checkoutHostId: _checkoutHostId,
                            ),
                      );
                    } else {
                      unawaited(_selectProject(projectId));
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  bool _checkoutReady(String? projectId) {
    if (projectId == null ||
        (_useProjectCheckout && !widget.supportsSharedCheckoutWorkspaces)) {
      return false;
    }
    return ref
            .read(workspaceCheckoutOptionsProvider(widget.hostId, projectId))
            .value
            ?.any(
              (checkout) => checkout.hostId == (_checkoutHostId ?? 'local'),
            ) ??
        false;
  }

  Widget _checkoutHostSelector(String projectId, bool enabled) {
    final hostId =
        ref.watch(
          workspaceCheckoutSelectionProvider(
            widget.hostId,
            widget.initialCheckoutHostId,
          ),
        ) ??
        'local';
    final options = ref.watch(
      workspaceCheckoutOptionsProvider(widget.hostId, projectId),
    );
    return options.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Could not load project locations: $error'),
      data: (checkouts) => AleraDropdownField<String>(
        value: checkouts.any((checkout) => checkout.hostId == hostId)
            ? hostId
            : null,
        labelText: 'Host',
        hintText: 'Select Registered Project Location',
        entries: [
          for (final checkout in checkouts)
            AleraDropdownFieldEntry(
              value: checkout.hostId,
              label: checkout.label,
            ),
        ],
        enabled: enabled,
        onChanged: (value) {
          ref
              .read(
                workspaceCheckoutSelectionProvider(
                  widget.hostId,
                  widget.initialCheckoutHostId,
                ).notifier,
              )
              .select(value);
          if (_fromPrompt) {
            unawaited(
              ref
                  .read(
                    promptWorkspaceControllerProvider(widget.hostId).notifier,
                  )
                  .selectProject(
                    projectId,
                    loadBranches: !_useProjectCheckout,
                    checkoutHostId: _checkoutHostId,
                    defaultAgentProfileId: widget.defaultAgentProfileId,
                  ),
            );
          } else {
            unawaited(_selectProject(projectId));
          }
        },
      ),
    );
  }
}
