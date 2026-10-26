import 'package:alera_agent_chat/alera_agent_chat.dart';

/// What Settings may claim about a provider instance. The vocabulary stays
/// honest: only a host-verified sign-in reads [ready]; a resolvable executable
/// with no verified sign-in reads [unknownSignIn].
enum AgentProviderStatusKind(final String label) {
  ready('Ready'),
  notInstalled('Not Installed'),
  setupRequired('Setup Required'),
  signInNeeded('Sign-In Needed'),
  unknownSignIn('Unknown Sign-In'),
  error('Error'),
  checking('Checking…'),
  off('Off'),
}

class const AgentProviderStatus({
  required final AgentProviderStatusKind kind,
  required final String detail,
}) {
  String get label => kind.label;
}

/// Why a [AgentProviderStatusKind.setupRequired] instance cannot start yet.
const String agentProviderSetupRequiredDetail =
    'This provider needs setup before it can start. Choose what it launches '
    'under Launch, then save.';

/// Derives the status line from a catalog row. [checking] is true while this
/// client has a forced re-check in flight for the row's host.
AgentProviderStatus agentProviderStatusOf(
  AgentChatProviderInstance instance, {
  bool checking = false,
}) {
  if (!instance.enabled) {
    return const AgentProviderStatus(
      kind: .off,
      detail: 'Not offered for new chats or provider switches.',
    );
  }
  if (checking) {
    return const AgentProviderStatus(
      kind: .checking,
      detail: 'Checking the installation and sign-in on this host.',
    );
  }
  // The host's reason is not shown: a fixed sentence cannot leak launch
  // details, and the instance is unconfigured rather than broken.
  if (instance.setupRequired) {
    return const AgentProviderStatus(
      kind: .setupRequired,
      detail: agentProviderSetupRequiredDetail,
    );
  }
  if (instance.installed == false) {
    return AgentProviderStatus(
      kind: .notInstalled,
      detail:
          instance.unavailableReason ??
          'The provider is not installed on this host.',
    );
  }
  final auth = instance.auth;
  if (auth.status == .signedOut && auth.checkedAt != null) {
    return AgentProviderStatus(
      kind: .signInNeeded,
      detail: auth.label ?? 'The provider reported that nobody is signed in.',
    );
  }
  if (!instance.available) {
    return AgentProviderStatus(
      kind: .error,
      detail:
          instance.unavailableReason ??
          'The runtime cannot start this provider.',
    );
  }
  if (auth.status == .signedIn && auth.checkedAt != null) {
    return AgentProviderStatus(
      kind: .ready,
      detail: auth.label ?? 'Installed and signed in.',
    );
  }
  return const AgentProviderStatus(
    kind: .unknownSignIn,
    detail:
        'Installed, but sign-in could not be verified. A chat may ask you to '
        'sign in.',
  );
}

/// `Checked 4m ago`, or `Not checked yet` when the host reported no time. A
/// time ahead of [now] (clock skew between hosts) reads as just now.
String agentProviderCheckedLabel(DateTime? checkedAt, DateTime now) {
  if (checkedAt == null) {
    return 'Not checked yet';
  }
  final age = now.difference(checkedAt);
  if (age < const Duration(minutes: 1)) {
    return 'Checked just now';
  }
  if (age < const Duration(hours: 1)) {
    return 'Checked ${age.inMinutes}m ago';
  }
  if (age < const Duration(days: 1)) {
    return 'Checked ${age.inHours}h ago';
  }
  return 'Checked ${age.inDays}d ago';
}

/// The oldest check time across [instances], which is what a host-wide
/// "Checked" label has to report so it never overstates freshness.
DateTime? agentProviderOldestCheck(Iterable<AgentChatProviderInstance> rows) {
  DateTime? oldest;
  for (final row in rows) {
    final checkedAt = row.checkedAt;
    if (checkedAt == null) {
      continue;
    }
    if (oldest == null || checkedAt.isBefore(oldest)) {
      oldest = checkedAt;
    }
  }
  return oldest;
}
