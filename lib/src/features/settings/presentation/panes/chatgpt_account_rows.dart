import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official ChatGPT copy from the Sign in with ChatGPT UX guidelines. These
/// labels keep OpenAI's sentence case instead of Alera's title case.
const String chatGptSignInLabel = 'Continue with ChatGPT';
const String chatGptManageUsageLabel = 'Manage usage';
const String chatGptPlanInUseLabel = 'Using ChatGPT plan';
final Uri chatGptUsageUri = Uri.parse('https://chatgpt.com/settings/usage');

/// One ChatGPT account registration reported by the runtime. [label] is
/// distinct per registration, even when two share an email address.
class const ChatGptAccount({
  required final String clientId,
  required final String label,
  required final bool connected,
  required final bool planEnabled,
}) {
  static ChatGptAccount? fromJson(Object? value) {
    if (value is! Map) return null;
    final clientId = value['clientId'];
    if (clientId is! String || clientId.isEmpty) return null;
    final label = value['label'];
    return ChatGptAccount(
      clientId: clientId,
      label: label is String && label.isNotEmpty ? label : 'ChatGPT',
      connected: value['connected'] == true,
      planEnabled: value['planEnabled'] == true,
    );
  }

  bool get ready => connected && planEnabled;
}

/// The OpenAI knot, tinted to the surrounding text color.
class const ChatGptLogo({super.key, final double size = AleraTokens.space16})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/agents/codex.svg',
      width: size,
      height: size,
      excludeFromSemantics: true,
      colorFilter: ColorFilter.mode(
        IconTheme.of(context).color ?? AleraTokens.foreground,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Small spinner sized like an icon so a busy button keeps its width.
class const ChatGptButtonSpinner({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: AleraTokens.space16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// The approved "Continue with ChatGPT" button: knot plus official label.
class const ChatGptSignInButton({
  super.key,
  required final VoidCallback? onPressed,
  final bool busy = false,
  final String? semanticsLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: busy ? const ChatGptButtonSpinner() : const ChatGptLogo(),
      label: Text(chatGptSignInLabel, semanticsLabel: semanticsLabel),
      onPressed: onPressed,
    );
  }
}

/// A settings row for one account registration: label, active badge and
/// state on the left; the actions that apply to its state on the right.
class const ChatGptAccountRow({
  super.key,
  required final ChatGptAccount account,
  required final bool active,
  required final List<Widget> actions,
}) extends StatelessWidget {
  String get _state {
    if (!account.connected) return 'Signed out.';
    if (!account.planEnabled) {
      return 'Plan usage isn’t allowed for this account yet.';
    }
    return active
        ? '$chatGptPlanInUseLabel.'
        : 'Signed in. Not used by AI Assist.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        account.label,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: .w500,
                        ),
                      ),
                    ),
                    if (active) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      const AleraBadge(
                        label: 'Active',
                        foregroundColor: AleraTokens.foreground,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  _state,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space16),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            alignment: .end,
            crossAxisAlignment: .center,
            children: actions,
          ),
        ],
      ),
    );
  }
}

/// First-use confirmation that AI Assist now draws on the ChatGPT plan. The
/// copy follows the official guideline verbatim.
Future<void> showChatGptPlanNotice(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AleraDialog(
        maxWidth: AleraTokens.dialogCompactWidth,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              const IconTheme(
                data: IconThemeData(color: AleraTokens.foreground),
                child: ChatGptLogo(size: AleraTokens.space32),
              ),
              const SizedBox(height: AleraTokens.space16),
              Semantics(
                header: true,
                child: Text(
                  'You’re using your ChatGPT plan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: .w600,
                  ),
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Eligible usage in this app uses your ChatGPT plan. Manage usage in your ChatGPT settings.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space24),
              Align(
                alignment: .centerRight,
                child: FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
