import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/github_star_prompt_eligibility.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Offers a one-time GitHub star prompt after the user has real project history.
///
/// Must sit under a [Navigator] route (shell home), not in
/// `MaterialApp.builder`. Declining or completing the flow mutes the prompt via
/// [SettingsController.markStarClicked].
class GitHubStarPromptWatch extends ConsumerStatefulWidget {
  const GitHubStarPromptWatch({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GitHubStarPromptWatch> createState() =>
      _GitHubStarPromptWatchState();
}

class _GitHubStarPromptWatchState extends ConsumerState<GitHubStarPromptWatch> {
  var _asked = false;
  var _promptQueued = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AleraSettings>(settingsControllerProvider, (previous, next) {
      _schedulePromptCheck();
    });
    ref.listen<AsyncValue<List<Project>>>(projectListProvider, (
      previous,
      next,
    ) {
      _schedulePromptCheck();
    });
    ref.listen<GitHubStarState>(gitHubStarControllerProvider, (previous, next) {
      _schedulePromptCheck();
    });
    _schedulePromptCheck();
    return widget.child;
  }

  void _schedulePromptCheck() {
    if (_asked || _promptQueued) {
      return;
    }
    _promptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptQueued = false;
      if (!mounted || _asked) {
        return;
      }
      unawaited(_maybePrompt());
    });
  }

  Future<void> _maybePrompt() async {
    if (_asked || !mounted) {
      return;
    }

    // Settings start as defaults and load async; refresh before deciding so a
    // previously muted install does not flash the dialog on cold start.
    await ref.read(settingsControllerProvider.notifier).load();
    if (!mounted || _asked) {
      return;
    }

    final settings = ref.read(settingsControllerProvider);
    final projects = ref.read(projectListProvider).asData?.value;
    final starState = ref.read(gitHubStarControllerProvider);
    if (projects == null) {
      return;
    }
    if (!shouldOfferGitHubStarPrompt(
      starClicked: settings.general.starClicked,
      projects: projects,
      starState: starState,
      now: DateTime.now().toUtc(),
    )) {
      return;
    }

    _asked = true;
    await _ask();
  }

  Future<void> _ask() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: 'Support Alera',
        message:
            'If this is useful, consider starring the repo. '
            'It helps more developers discover it.',
        confirmLabel: 'Star On GitHub',
        cancelLabel: 'Not Now',
      ),
    );
    if (!mounted) {
      return;
    }
    if (accepted == true) {
      await _starOrOpenUrl();
    }
    if (!mounted) {
      return;
    }
    await ref.read(settingsControllerProvider.notifier).markStarClicked();
  }

  Future<void> _starOrOpenUrl() async {
    final starState = ref.read(gitHubStarControllerProvider);
    if (starState == GitHubStarState.notStarred ||
        starState == GitHubStarState.error) {
      await ref.read(gitHubStarControllerProvider.notifier).star();
    }
    if (!mounted) {
      return;
    }
    if (ref.read(gitHubStarControllerProvider) == GitHubStarState.starred) {
      return;
    }
    try {
      await ref
          .read(externalUriLauncherProvider)
          .open(Uri.parse(aleraGitHubUrl));
    } catch (_) {
      // Opening the browser is best-effort; the mute still applies.
    }
  }
}
