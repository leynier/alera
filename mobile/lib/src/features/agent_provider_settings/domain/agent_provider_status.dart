import 'package:alera_agent_chat/alera_agent_chat.dart';

/// The one status line a provider row shows. Ready means the host verified
/// sign-in, never only that an executable resolves; anything less proven
/// reads as Unknown Sign-In.
enum AgentProviderStatus {
  ready('Ready'),
  notInstalled('Not Installed'),
  setupRequired('Setup Required'),
  signInNeeded('Sign-In Needed'),
  unknownSignIn('Unknown Sign-In'),
  error('Error'),
  checking('Checking'),
  off('Off');

  AgentProviderStatus(this.label);

  final String label;

  bool get healthy => this == ready || this == unknownSignIn;
}

/// Why a [AgentProviderStatus.setupRequired] instance cannot start yet. A
/// fixed sentence rather than the host's reason, so it cannot leak launch
/// details. Phones cannot edit launch settings, so it points at the desktop.
const String agentProviderSetupRequiredDetail =
    'This provider needs setup before it can start. Set it up in Settings > '
    'Providers in the Alera desktop app.';

AgentProviderStatus agentProviderStatusOf(
  AgentChatProviderInstance instance, {
  bool checking = false,
}) {
  if (!instance.enabled) return .off;
  if (checking) return .checking;
  if (instance.setupRequired) return .setupRequired;
  if (instance.installed == false) return .notInstalled;
  final auth = instance.auth;
  if (auth.status == AgentChatProviderAuthStatus.signedOut) {
    return .signInNeeded;
  }
  if (!instance.available) return .error;
  if (auth.status == AgentChatProviderAuthStatus.signedIn && auth.verified) {
    return .ready;
  }
  return .unknownSignIn;
}

/// "Checked 2m ago" for the last time the host verified a provider.
String agentProviderCheckedLabel(DateTime? checkedAt, DateTime now) {
  if (checkedAt == null) return 'Not checked yet';
  final elapsed = now.toUtc().difference(checkedAt.toUtc());
  if (elapsed.inSeconds < 60) return 'Checked just now';
  if (elapsed.inMinutes < 60) return 'Checked ${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return 'Checked ${elapsed.inHours}h ago';
  return 'Checked ${elapsed.inDays}d ago';
}

/// The newest check across the catalog, which is what Refresh renews.
DateTime? agentProviderLastChecked(List<AgentChatProviderInstance> providers) {
  DateTime? latest;
  for (final instance in providers) {
    final checked = instance.checkedAt;
    if (checked != null && (latest == null || checked.isAfter(latest))) {
      latest = checked;
    }
  }
  return latest;
}

/// The wire name of a secret option, as the host declares secrets: plain for
/// an environment variable, `option:<key>` for a provider option.
String agentProviderSecretOptionName(String name) =>
    name.startsWith('option:') ? name : 'option:$name';
