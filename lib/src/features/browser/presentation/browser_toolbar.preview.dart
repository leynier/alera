import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/presentation/browser_toolbar.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Loading', group: 'Browser')
Widget browserToolbarLoadingPreview() {
  return const _BrowserToolbarPreview();
}

class const _BrowserToolbarPreview() extends StatefulWidget {
  @override
  State<_BrowserToolbarPreview> createState() => _BrowserToolbarPreviewState();
}

class _BrowserToolbarPreviewState extends State<_BrowserToolbarPreview> {
  final TextEditingController _addressController = TextEditingController(
    text: 'https://docs.alera.dev/browser',
  );
  final FocusNode _addressFocusNode = FocusNode();

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = BrowserPage(
      pageId: 'page-preview',
      workspaceId: 'workspace-preview',
      profileId: 'default',
      initialUrl: Uri.parse('https://docs.alera.dev'),
      createdAt: .utc(2026, 7, 27),
    );
    final state = BrowserPageState.initial(page).copyWith(
      url: Uri.parse('https://docs.alera.dev/browser'),
      title: 'Browser Tabs',
      loadPhase: .started,
      loadProgress: 0.42,
      canGoBack: true,
      security: const BrowserSecurityState(
        level: .secure,
        origin: 'https://docs.alera.dev',
      ),
    );
    return SizedBox(
      width: AleraTokens.desktopPreviewWidth,
      child: BrowserToolbar(
        state: state,
        addressController: _addressController,
        addressFocusNode: _addressFocusNode,
        profileLabel: 'Default',
        onBack: () {},
        onForward: null,
        onStopOrReload: () {},
        onSubmitAddress: (_) {},
        onShowSecurity: () {},
        onSelectProfile: () {},
        onShowDownloads: () {},
        onOpenDevTools: () {},
        onOpenExternally: () {},
      ),
    );
  }
}
