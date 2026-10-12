import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:alera/src/features/workbench/application/workspace_git_progress.dart';
import 'package:alera/src/features/workbench/presentation/workspace_details_review_rows.dart';
import 'package:alera/src/features/workbench/presentation/workspace_details_presence.dart';
import 'package:flutter/services.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/workbench/application/background_operations.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission_job.dart';
import 'package:alera/src/features/workbench/application/workspace_details_toggle_signal.dart';

import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:alera/src/features/workbench/application/workspace_details_provider.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_comparison_base.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workbench_hand_off_launchers.dart';
import 'package:alera/src/features/workbench/presentation/workspace_branch_dialog.dart';
import 'package:alera/src/features/workbench/presentation/workspace_comparison_dialog.dart';
import 'package:alera/src/features/workbench/presentation/workspace_external_actions.dart'
    as external_actions;
import 'package:alera/src/features/workbench/presentation/workspace_git_submission_dialog.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/host_routed_git_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_details_overlay_actions.dart';
part 'workspace_details_overlay_card.dart';

class const WorkspaceDetailsOverlay({
  super.key,
  required this.workspace,
  required this.sourceControlScope,
  required this.child,
}) extends ConsumerStatefulWidget {
  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final Widget child;
  @override
  ConsumerState<WorkspaceDetailsOverlay> createState() =>
      _WorkspaceDetailsOverlayState();
}

class _WorkspaceDetailsOverlayState
    extends ConsumerState<WorkspaceDetailsOverlay> {
  final _anchor = GlobalKey();
  final _portal = OverlayPortalController();
  final _inlineFocus = FocusScopeNode(debugLabel: 'Workspace Details');
  final _popupFocus = FocusScopeNode(debugLabel: 'Workspace Details Popup');
  final _toggleFocus = FocusScopeNode(debugLabel: 'Workspace Details Toggle');
  @override
  void dispose() {
    _inlineFocus.dispose();
    _popupFocus.dispose();
    _toggleFocus.dispose();
    super.dispose();
  }

  bool _popupOpen = false;
  bool _inline = false;
  bool _running = false;
  WorkspaceGitSubmission? _pending;

  @override
  void didUpdateWidget(WorkspaceDetailsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.id != widget.workspace.id ||
        oldWidget.workspace.hostId != widget.workspace.hostId ||
        oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.sourceControlScope?.path != widget.sourceControlScope?.path) {
      _popupOpen = false;
      _pending = null;
      _running = false;
    }
  }

  WorkspacePullRequestScope get _scope => WorkspacePullRequestScope(
    workspaceId: widget.workspace.id,
    repoPath: widget.sourceControlScope?.path ?? widget.workspace.path,
    branch: widget.sourceControlScope?.isWorkspaceRoot == true
        ? widget.workspace.branch
        : null,
    sourceBranch: widget.workspace.sourceBranch,
    providerOverride: ref
        .read(
          effectiveHostingProviderOverrideProvider(widget.workspace.projectId),
        )
        .value,
  );

  void _changeState(VoidCallback action) => setState(action);

  void _closePopup() {
    final restore = _popupFocus.hasFocus || _toggleFocus.hasFocus;
    _portal.hide();
    setState(() => _popupOpen = false);
    if (restore) {
      KeyboardCommandDispatcher(ref: ref, context: context).focusActivePane();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.viewPrefs.workspaceDetailsHiddenIds.contains(
          widget.workspace.id,
        ),
      ),
    );
    ref.listen(workspaceDetailsToggleSignalProvider(widget.workspace.id), (
      previous,
      next,
    ) {
      if (previous == next) return;
      if (_inline) {
        final restore =
            !hidden && (_inlineFocus.hasFocus || _toggleFocus.hasFocus);
        ref
            .read(workbenchControllerProvider.notifier)
            .toggleWorkspaceDetails(widget.workspace.id);
        if (restore) {
          KeyboardCommandDispatcher(
            ref: ref,
            context: context,
          ).focusActivePane();
        }
      } else if (_popupOpen) {
        _closePopup();
      } else {
        setState(() => _popupOpen = true);
        _portal.show();
      }
    });
    final state = ref.read(workbenchControllerProvider);
    final runtime = ref.read(terminalRuntimeProvider);
    final searches = [
      for (final tab in state.tabsFor(widget.workspace.id))
        ?runtime.peekSession(tab.id)?.searchController,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(searches),
      child: widget.child,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final searchOpen = searches.any((search) => search.isOpen);
          final inline =
              !searchOpen &&
              constraints.maxWidth >= AleraTokens.wideContentBreakpoint &&
              constraints.maxHeight >=
                  AleraTokens.workspaceDetailsMinHeight +
                      AleraTokens.space48 +
                      AleraTokens.space16;
          if (inline != _inline) {
            _inline = inline;
            _popupOpen = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _portal.hide();
            });
          }
          final showCard = inline && !hidden;
          final cardWidth = (constraints.maxWidth - AleraTokens.space16 * 2)
              .clamp(0.0, AleraTokens.workspaceDetailsWidth);
          return Stack(
            fit: StackFit.expand,
            children: [
              child!,
              Positioned(
                top:
                    searchOpen ||
                        constraints.maxWidth < AleraTokens.workspaceDetailsWidth
                    ? null
                    : AleraTokens.space4,
                bottom:
                    searchOpen ||
                        constraints.maxWidth < AleraTokens.workspaceDetailsWidth
                    ? AleraTokens.space4
                    : null,
                left: constraints.maxWidth < AleraTokens.workspaceDetailsWidth
                    ? AleraTokens.space8
                    : null,
                right: constraints.maxWidth < AleraTokens.workspaceDetailsWidth
                    ? null
                    : AleraTokens.space48 * 3 + AleraTokens.space8,
                child: FocusScope(
                  node: _toggleFocus,
                  child: OverlayPortal(
                    controller: _portal,
                    overlayChildBuilder: (context) {
                      final overlaySize = MediaQuery.sizeOf(context);
                      final box =
                          _anchor.currentContext?.findRenderObject()
                              as RenderBox?;
                      final anchor = box == null
                          ? Offset.zero
                          : box.localToGlobal(Offset.zero);
                      final width =
                          (overlaySize.width - AleraTokens.space16 * 2).clamp(
                            0.0,
                            AleraTokens.workspaceDetailsWidth,
                          );
                      final left = (anchor.dx + (box?.size.width ?? 0) - width)
                          .clamp(
                            AleraTokens.space8,
                            overlaySize.width - width - AleraTokens.space8,
                          );
                      final topLimit =
                          (overlaySize.height -
                                  AleraTokens.workspaceDetailsMinHeight -
                                  AleraTokens.space8)
                              .clamp(AleraTokens.space8, double.infinity);
                      final top =
                          (anchor.dy +
                                  (box?.size.height ?? 0) +
                                  AleraTokens.space8)
                              .clamp(AleraTokens.space8, topLimit);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _closePopup,
                            ),
                          ),
                          Positioned(
                            left: left,
                            top: top,
                            width: width,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    overlaySize.height -
                                    top -
                                    AleraTokens.space8,
                              ),
                              child: SingleChildScrollView(
                                child: Consumer(
                                  builder: (context, cardRef, _) => _card(
                                    cardRef,
                                    popup: true,
                                    availableHeight:
                                        overlaySize.height -
                                        top -
                                        AleraTokens.space8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                    child: AleraIconButton(
                      key: _anchor,
                      icon: AleraIcons.review,
                      tooltip: 'Toggle Workspace Details',
                      onPressed: () => KeyboardCommandDispatcher(
                        ref: ref,
                        context: context,
                      ).dispatch(.toggleWorkspaceDetails),
                    ),
                  ),
                ),
              ),
              if (showCard && cardWidth >= AleraTokens.workspaceDetailsMinWidth)
                Positioned(
                  top: AleraTokens.space48,
                  right: AleraTokens.space8,
                  width: cardWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          constraints.maxHeight -
                          AleraTokens.space48 -
                          AleraTokens.space8,
                    ),
                    child: SingleChildScrollView(
                      child: Consumer(
                        builder: (context, cardRef, _) => _card(
                          cardRef,
                          availableHeight:
                              constraints.maxHeight -
                              AleraTokens.space48 -
                              AleraTokens.space8,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
