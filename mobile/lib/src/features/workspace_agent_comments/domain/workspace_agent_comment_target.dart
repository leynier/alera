import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';

/// Where queued comments go: an agent already running in a tab, or a new tab
/// opened from an Agent Profile with the comments as its starting prompt.
sealed class const WorkspaceAgentCommentTarget();

class const RunningAgentCommentTarget(final AgentPresenceSummary agent)
    extends WorkspaceAgentCommentTarget;

class const AgentProfileCommentTarget(final AgentProfileSummary profile)
    extends WorkspaceAgentCommentTarget;
