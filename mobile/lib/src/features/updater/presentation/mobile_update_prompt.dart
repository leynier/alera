import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/features/updater/application/mobile_update_providers.dart';
import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum _MobileUpdateAction { copyLink, download }

/// Offers the newest Android build once per launch.
///
/// Declining is remembered only for the session: the check runs when the app
/// opens, so the next launch asks again. This must be mounted inside a route
/// rather than in `MaterialApp.builder`, which sits above the Navigator the
/// dialog needs.
class MobileUpdatePrompt extends ConsumerStatefulWidget {
  const MobileUpdatePrompt({
    super.key,
    required this.child,
    this.copyLink = _copyToClipboard,
    this.openUrl = _launchExternalBrowser,
  });

  final Widget child;

  /// Injected so tests do not reach the platform clipboard.
  final Future<void> Function(String link) copyLink;

  /// Injected so tests do not reach the platform's URL launcher.
  final Future<bool> Function(Uri url) openUrl;

  @override
  ConsumerState<MobileUpdatePrompt> createState() => _MobileUpdatePromptState();
}

class _MobileUpdatePromptState extends ConsumerState<MobileUpdatePrompt> {
  var _asked = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<MobileRelease?>>(availableMobileUpdateProvider, (
      previous,
      next,
    ) {
      final release = next.value;
      if (release != null) {
        _promptOnce(release);
      }
    });
    final release = ref.watch(availableMobileUpdateProvider).value;
    if (release != null) {
      _promptOnce(release);
    }
    return widget.child;
  }

  void _promptOnce(MobileRelease release) {
    if (_asked) {
      return;
    }
    _asked = true;
    // The provider can resolve mid-build, and a dialog cannot be pushed while
    // the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _ask(release);
    });
  }

  Future<void> _ask(MobileRelease release) async {
    final action = await showDialog<_MobileUpdateAction>(
      context: context,
      builder: (context) =>
          _MobileUpdateDialog(version: release.version.toString()),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case _MobileUpdateAction.copyLink:
        await widget.copyLink(release.apkUrl.toString());
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download link copied.')));
        return;
      case _MobileUpdateAction.download:
        final opened = await widget.openUrl(release.apkUrl);
        if (opened || !mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the download.')),
        );
        return;
      case null:
        return;
    }
  }
}

class _MobileUpdateDialog extends StatelessWidget {
  const _MobileUpdateDialog({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Update available', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Text(
              'Alera $version is available. Downloading opens the APK in your '
              'browser, and Android asks to install it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_MobileUpdateAction.copyLink),
                child: const Text('Copy Link'),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_MobileUpdateAction.download),
                    child: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copyToClipboard(String link) {
  return Clipboard.setData(ClipboardData(text: link));
}

Future<bool> _launchExternalBrowser(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
