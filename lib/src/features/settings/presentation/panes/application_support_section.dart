import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double kSupportControlHeight = 34;

class SupportAleraSection extends ConsumerWidget {
  const SupportAleraSection({super.key, required this.state});

  final GitHubStarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Text(
            'Support Alera',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AleraPanel(
          children: <Widget>[
            AleraSettingRow(
              title: 'Star Alera on GitHub',
              description: null,
              child: _StarControl(
                state: state,
                onStar: () =>
                    ref.read(gitHubStarControllerProvider.notifier).star(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StarControl extends StatelessWidget {
  const _StarControl({required this.state, required this.onStar});

  final GitHubStarState state;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedSwitcher(
        duration: AleraTokens.durationMid,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    return switch (state) {
      GitHubStarState.loading => const _StarSkeleton(
        key: ValueKey<String>('loading'),
      ),
      GitHubStarState.notStarred => _StarButton(
        key: const ValueKey<String>('not-starred'),
        label: 'Star',
        onPressed: onStar,
      ),
      GitHubStarState.starring => const _StarButton(
        key: ValueKey<String>('starring'),
        label: 'Starring…',
        busy: true,
      ),
      GitHubStarState.starred => const _StarThanks(
        key: ValueKey<String>('starred'),
      ),
      GitHubStarState.error => _StarButton(
        key: const ValueKey<String>('error'),
        label: 'Try again',
        onPressed: onStar,
      ),
      GitHubStarState.hidden => const SizedBox.shrink(
        key: ValueKey<String>('hidden'),
      ),
    };
  }
}

@visibleForTesting
Widget buildStarControlForTesting({
  required GitHubStarState state,
  required VoidCallback onStar,
}) {
  return _StarControl(state: state, onStar: onStar);
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSupportControlHeight,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AleraTokens.foreground,
                ),
              )
            : const Icon(AleraIcons.star, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _StarThanks extends StatelessWidget {
  const _StarThanks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Thanks for starring Alera',
      liveRegion: true,
      child: SizedBox(
        height: kSupportControlHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(AleraIcons.star, size: 16, color: AleraTokens.warning),
            const SizedBox(width: AleraTokens.space6),
            Text(
              'Thanks for the support!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarSkeleton extends StatelessWidget {
  const _StarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kSupportControlHeight,
      width: 110,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
    );
  }
}
