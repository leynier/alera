part of 'workspace_details_overlay.dart';

extension on _WorkspaceDetailsOverlayState {
  Widget _card(
    WidgetRef cardRef, {
    bool popup = false,
    required double availableHeight,
  }) {
    cardRef.watch(
      effectiveHostingProviderOverrideProvider(widget.workspace.projectId),
    );
    final workspace = widget.workspace;
    final issue = cardRef.watch(workspaceLinkedIssueProvider(workspace.id));
    final related = cardRef.watch(
      workbenchControllerProvider.select(
        (state) => _relatedWorkspaces(state, workspace.id),
      ),
    );
    final targets = cardRef.watch(sshTargetsProvider).value ?? const [];
    final host = targets
        .where((target) => target.id == workspace.hostId)
        .firstOrNull;
    final hostLabel = workspace.isRemote
        ? host?.alias ?? workspace.hostId
        : Platform.localHostname;
    final scope = _scope;
    final details = widget.sourceControlScope == null
        ? null
        : cardRef.watch(workspaceDetailsProvider(scope));
    final data = details?.value;
    final progress = widget.sourceControlScope == null
        ? null
        : cardRef.watch(workspaceGitProgressProvider(scope));
    final busy =
        _running ||
        progress?.running == true ||
        (data?.sourceControl.isBusy ?? false) ||
        (data?.pullRequest?.isBusy ?? false);
    final density = workspaceDetailsDensity(availableHeight);
    Widget icon(IconData icon) => Icon(icon);
    final gitError = progress?.error;
    final card = FocusScope(
      node: popup ? _popupFocus : _inlineFocus,
      onKeyEvent: !popup
          ? null
          : (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _closePopup();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      child: AleraWorkspaceDetailsCard(
        density: density,
        onOptions: (anchor) => unawaited(_detailsOptions(anchor)),
        afterWorkspace: WorkspaceDetailsAgentRows(
          workspace: workspace,
          density: density,
        ),
        afterBranch: widget.sourceControlScope == null
            ? null
            : WorkspaceDetailsReviewRows(
                key: ValueKey(scope),
                scope: scope,
                compact: density != WorkspaceDetailsDensity.full,
              ),
        workspaceRows: [
          AleraWorkspaceDetailRow(
            label: hostLabel,
            leading: AleraHostOsIcon(
              os: workspace.isRemote
                  ? sshTargetHostOs(host)
                  : HostOs.parse(Platform.operatingSystem),
              size: AleraTokens.iconMd,
            ),
            onMenu: (anchor) => unawaited(_hostMenu(anchor)),
            pressOpensMenu: true,
          ),
          AleraWorkspaceDetailRow(
            label:
                'Open In ${cardRef.read(workspaceFolderOpenerProvider).fileManagerLabel}',
            leading: icon(AleraIcons.folder),
            hint: workspace.isRemote
                ? 'This folder is on another host. Use Copy Path.'
                : null,
            onPressed: workspace.isRemote
                ? null
                : () => unawaited(
                    external_actions.openWorkspaceFolder(
                      context,
                      ref,
                      workspace,
                    ),
                  ),
            onMenu: (anchor) => unawaited(_openMenu(anchor)),
          ),
          if (issue != null)
            AleraWorkspaceDetailRow(
              label: issue.title == null
                  ? issue.reference
                  : '${issue.reference}: ${issue.title}',
              subtitle: issue.fetchError != null
                  ? 'Could not refresh the issue'
                  : issue.displayState,
              subtitleColor: issue.fetchError == null
                  ? null
                  : AleraTokens.error,
              leading: LinkedIssueStateIcon(
                state: issue.state,
                size: AleraTokens.iconMd,
              ),
              hint: workspaceLinkedIssueTooltip(issue),
              onPressed: () => _issueAction(openLinkedIssueMenuAction),
              onMenu: (anchor) => unawaited(_issueMenu(anchor)),
            ),
          ?_relatedRow(related),
        ],
        gitRows: [
          if (widget.sourceControlScope != null) ...[
            AleraWorkspaceDetailRow(
              label:
                  data?.sourceControl.repositoryState.branch ??
                  workspace.branch ??
                  'Branch',
              subtitle: data != null
                  ? 'Compare against ${data.comparison.baseRef ?? 'HEAD'}'
                  : details?.hasError == true
                  ? 'Comparison failed. Select a base.'
                  : null,
              subtitleColor: data == null && details?.hasError == true
                  ? AleraTokens.error
                  : null,
              hasMenu: true,
              leading: icon(AleraIcons.gitBranch),
              trailing: data == null ? null : _branchSync(data),
              hint: details?.hasError == true
                  ? details!.error.toString()
                  : data == null
                  ? null
                  : _branchSyncHint(data),
              pressOpensMenu: data != null,
              onPressed: busy || details?.hasError != true
                  ? null
                  : () => unawaited(_recoverComparisonBase()),
              onMenu: busy
                  ? null
                  : data != null
                  ? (anchor) => unawaited(_branchMenu(data, anchor))
                  : details?.hasError == true
                  ? (_) => unawaited(_recoverComparisonBase())
                  : null,
            ),
            AleraWorkspaceDetailRow(
              label:
                  progress?.phase ??
                  _pending?.pendingLabel ??
                  data?.quickAction.label ??
                  'Commit',
              hasMenu: true,
              leading: progress?.running == true
                  ? const AleraWorkspaceDetailSpinner()
                  : gitError != null
                  ? const Icon(AleraIcons.error, color: AleraTokens.error)
                  : progress?.completed == true
                  ? const Icon(AleraIcons.success, color: AleraTokens.success)
                  : icon(AleraIcons.gitPush),
              subtitle: progress == null
                  ? null
                  : gitError ??
                        '${progress.elapsed.inSeconds}s${progress.output == null ? '' : ' · ${progress.output}'}',
              subtitleColor: gitError == null ? null : AleraTokens.error,
              trailing: gitError == null
                  ? null
                  : AleraIconButton(
                      icon: AleraIcons.close,
                      tooltip: 'Dismiss Error',
                      minSize: AleraTokens.iconButtonXs,
                      iconSize: AleraTokens.iconSm,
                      onPressed: () => cardRef
                          .read(workspaceGitProgressProvider(scope).notifier)
                          .dismiss(),
                    ),
              hint:
                  progress?.error ??
                  progress?.output ??
                  (details?.hasError == true
                      ? details!.error.toString()
                      : data?.quickAction.hint),
              onPressed: busy
                  ? null
                  : progress?.error != null && progress?.retry != null
                  ? progress!.retry
                  : _pending != null
                  ? () => unawaited(_execute(_pending!, scope))
                  : data?.quickAction.action == null
                  ? null
                  : () => unawaited(
                      _requestAction(data!, data.quickAction.action!, scope),
                    ),
              onMenu: data == null || busy
                  ? null
                  : (anchor) => unawaited(_gitMenu(data, scope, anchor)),
            ),
            AleraWorkspaceDetailRow(
              label: details?.isLoading == true && data == null
                  ? 'Loading…'
                  : 'Changes',
              leading: icon(AleraIcons.diff),
              hint: details?.hasError == true
                  ? details!.error.toString()
                  : null,
              trailing: data == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${data.comparison.added}',
                          style: AleraTokens.monoCompactStyle.copyWith(
                            color: AleraTokens.success,
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space6),
                        Text(
                          '-${data.comparison.removed}',
                          style: AleraTokens.monoCompactStyle.copyWith(
                            color: AleraTokens.error,
                          ),
                        ),
                      ],
                    ),
              onPressed: data == null
                  ? () => ref.invalidate(workspaceDetailsProvider(scope))
                  : _revealSourceControl,
            ),
          ],
        ],
      ),
    );
    return widget.sourceControlScope == null
        ? card
        : WorkspaceSourceControlPresence(
            path: scope.repoPath,
            child: WorkspaceDetailsPresence(
              key: ValueKey(scope),
              scope: scope,
              child: card,
            ),
          );
  }
}
