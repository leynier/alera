import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/updater/application/mobile_update_providers.dart';
import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.openUrl = _launchExternally,
  });

  final Widget child;

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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: 'Update Available',
        message:
            'Alera ${release.version} is available. '
            'Downloading opens the APK in your browser, and Android asks to '
            'install it.',
        confirmLabel: 'Download',
        cancelLabel: 'Later',
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }
    final opened = await widget.openUrl(release.apkUrl);
    if (opened || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the download.')),
    );
  }
}

Future<bool> _launchExternally(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
