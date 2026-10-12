import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_clipboard_paste_action.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/preferred_source_branch.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/domain/project_selection_order.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_notice.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_selection.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'welcome_dashboard_actions.dart';
part 'welcome_dashboard_view.dart';
part 'welcome_dashboard_composer.dart';

/// Home shown when no workspace is open.
class const WelcomeDashboard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WelcomeDashboard> createState() => _WelcomeDashboardState();
}

class _WelcomeDashboardState extends ConsumerState<WelcomeDashboard> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final PromptWorkspaceClipboard _clipboard =
      const NativePromptWorkspaceClipboard();
  ProjectHostEnrollmentController? _hostEnrollment;

  String? _explicitProjectId;
  String? _explicitProfileId;
  bool _hasBoundProject = false;
  String? _boundProjectId;
  Project? _boundProject;
  bool _useProjectCheckout = true;
  String? _selectedHostId;
  String? _selectedParentId;
  int _branchGeneration = 0;
  bool _branchesAwaitEnrollment = false;
  bool _loadingBranches = false;
  List<String> _branches = const <String>[];
  String? _sourceBranch;
  String? _error;

  @override
  void dispose() {
    _hostEnrollment?.removeListener(_onHostEnrollmentChanged);
    _hostEnrollment?.dispose();
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  /// The capability future is false on the first frame and on any later
  /// failure. Swap the adder on the same controller: disposing it here would
  /// drop the path field while Add to Host is still mounted.
  ProjectHostEnrollmentController _ensureHostEnrollment(bool supportsHosts) {
    final current = _hostEnrollment;
    final adder = supportsHosts ? projectHostAdder(ref) : null;
    if (current == null) {
      final next = ProjectHostEnrollmentController(adder)
        ..addListener(_onHostEnrollmentChanged);
      _hostEnrollment = next;
      return next;
    }
    if (current.supported != supportsHosts) {
      current.replaceAdder(adder);
    }
    return current;
  }

  void _update(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  Project? _projectFor(List<Project> projects, String? activeProjectId) {
    final explicit = _explicitProjectId;
    if (explicit != null) {
      for (final project in projects) {
        if (project.id == explicit) {
          return project;
        }
      }
    }
    if (activeProjectId != null) {
      for (final project in projects) {
        if (project.id == activeProjectId) {
          return project;
        }
      }
    }
    return projects.firstOrNull;
  }

  AgentProfile? _profileFor(List<AgentProfile> profiles, String? defaultId) {
    final explicit = _explicitProfileId;
    if (explicit != null) {
      for (final profile in profiles) {
        if (profile.id == explicit) {
          return profile;
        }
      }
    }
    if (defaultId != null) {
      for (final profile in profiles) {
        if (profile.id == defaultId) {
          return profile;
        }
      }
    }
    return profiles.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final workbench = ref.watch(workbenchControllerProvider);
    final profilesAsync = ref.watch(agentProfilesProvider);
    final sshTargets = ref.watch(sshTargetsProvider);
    final remoteHosts = ref.watch(remoteHostsControllerProvider).hosts;
    final defaultProfileId = ref
        .watch(settingsControllerProvider)
        .agents
        .defaultAgentProfileId;
    // Watch directly. exists() is false when this screen builds before the
    // sidebar has read the capability, and the composer would then never see
    // the later value.
    final supportsProjectHosts =
        ref.watch(projectHostsSupportedProvider).value ?? false;
    final hostEnrollment = _ensureHostEnrollment(supportsProjectHosts);
    final projects = sortProjectsForSelection(<Project>[
      for (final project in workbench.projects) hostEnrollment.resolve(project),
    ]);
    final project = _projectFor(projects, workbench.activeProjectId);
    _syncBoundProject(project);
    final profiles = profilesAsync.asData?.value;
    final selectedProfile = profiles == null
        ? null
        : _profileFor(profiles, defaultProfileId);
    final parents = _parentWorkspaces(workbench);

    return Scaffold(
      backgroundColor: AleraTokens.bg,
      body: SafeArea(
        child: _HomeComposerFrame(
          child: _buildBody(
            workbench: workbench,
            project: project,
            projects: projects,
            profilesAsync: profilesAsync,
            profiles: profiles,
            profile: selectedProfile,
            sshTargets: sshTargets,
            remoteHosts: remoteHosts,
            parents: parents,
            hostEnrollment: hostEnrollment,
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required WorkbenchState workbench,
    required Project? project,
    required List<Project> projects,
    required AsyncValue<List<AgentProfile>> profilesAsync,
    required List<AgentProfile>? profiles,
    required AgentProfile? profile,
    required AsyncValue<List<SshTarget>> sshTargets,
    required List<RemoteHostView> remoteHosts,
    required List<Workspace> parents,
    required ProjectHostEnrollmentController hostEnrollment,
  }) {
    final heading = project == null
        ? const _HomeComposerQuestion()
        : _HomeComposerHeading(
            projectName: project.name,
            onPickProject: (context) => _pickProject(context, projects),
          );
    if (project == null || profiles == null || profiles.isEmpty) {
      return Column(
        mainAxisSize: .min,
        children: <Widget>[
          heading,
          _HomeComposerSetup(
            needsProject: project == null,
            needsProfile:
                (profiles != null && profiles.isEmpty) ||
                profilesAsync.hasError,
            profileError: profilesAsync.hasError
                ? userFacingExceptionMessage(profilesAsync.error!)
                : null,
            loadingProfiles:
                project != null && profiles == null && !profilesAsync.hasError,
            onAddProject: () => unawaited(showAddProjectFlow(context, ref)),
            onCreateProfile: () => unawaited(
              openSettingsDialog(context, initialSectionId: 'agentProfiles'),
            ),
          ),
        ],
      );
    }
    final checkout = _useProjectCheckout || !project.isGitRepository;
    final hostError = _hostSelectionError(sshTargets);
    final enrollment = _enrollmentFor(project);
    return _HomeComposerReady(
      heading: heading,
      promptController: _promptController,
      promptFocusNode: _promptFocusNode,
      profile: profile!,
      fieldsReady: _fieldsReady(project: project),
      onSend: () => unawaited(_submit()),
      onPaste: _pastePromptClipboard,
      onPickProfile: (context) => _pickProfile(context, profiles),
      hostLabel: remoteHostViewLabel(remoteHosts, _selectedHostId),
      hostIsLocal: normalizedRemoteHostId(_selectedHostId) == null,
      onPickHost: (context) => _pickHost(context, remoteHosts),
      parentLabel: _selectedParentLabel(parents, workbench),
      showParent: parents.isNotEmpty,
      onPickParent: (context) => _pickParent(context, parents, workbench),
      locationLabel: _locationLabel(project),
      canChangeLocation: project.isGitRepository,
      locationIsWorktree: !checkout,
      onPickLocation: _pickLocation,
      enrollmentNotice: enrollment == .enrolled
          ? null
          : ProjectHostEnrollmentNotice(
              enrollment: enrollment,
              projectName: project.name,
              hostLabel: remoteHostViewLabel(remoteHosts, _selectedHostId),
              controller: hostEnrollment,
              onAdd: _addProjectToSelectedHost,
            ),
      messages: <String>[
        ?_error,
        if (hostError != null && hostError != _error) hostError,
      ],
    );
  }
}
