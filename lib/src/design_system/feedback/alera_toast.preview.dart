import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:flutter/material.dart';

// Interactive preview: tap a button to dispatch a toast, rendered by the host
// mounted in the same overlay (top-right), exactly as the app wires it.
@AleraPreview(name: 'Toasts', group: 'Toast', size: Size(440, 260))
WidgetBuilder aleraToastPreview() =>
    (context) => Stack(
      children: <Widget>[
        Center(
          child: Wrap(
            spacing: AleraTokens.space8,
            children: <Widget>[
              FilledButton(
                onPressed: () => AleraToast.show(
                  context,
                  message: 'Workspace created',
                  tone: .success,
                ),
                child: const Text('Success'),
              ),
              FilledButton(
                onPressed: () => AleraToast.show(
                  context,
                  message: 'Workspace created with setup warnings',
                  tone: .warning,
                  duration: AleraTokens.toastLongDuration,
                ),
                child: const Text('Warning'),
              ),
              FilledButton(
                onPressed: () => AleraToast.show(
                  context,
                  message: 'Something went wrong',
                  tone: .error,
                ),
                child: const Text('Error'),
              ),
              FilledButton(
                onPressed: () =>
                    AleraToast.show(context, message: 'Heads up', tone: .info),
                child: const Text('Info'),
              ),
            ],
          ),
        ),
        const AleraToastHost(),
      ],
    );

@AleraPreview(name: 'With action', group: 'Toast', size: Size(440, 220))
WidgetBuilder aleraToastActionPreview() =>
    (context) => Stack(
      children: <Widget>[
        Center(
          child: FilledButton(
            onPressed: () => AleraToast.show(
              context,
              message: 'Build Mac disconnected. Reconnecting…',
              tone: .warning,
              duration: AleraToast.longDuration,
              actionLabel: 'Open Host',
              onAction: () {},
            ),
            child: const Text('Show Toast'),
          ),
        ),
        const AleraToastHost(),
      ],
    );

Future<String?> _previewClarifier(String message) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  return 'The push was rejected because the remote branch has commits you do '
      'not have. Pull or rebase, then push again.';
}

// The host shows the original error with a caption while the fake clarifier
// runs, then the rewrite with Copy Original, as Clarify Error Messages does.
@AleraPreview(name: 'Clarified error', group: 'Toast', size: Size(440, 260))
WidgetBuilder aleraToastClarifiedPreview() =>
    (context) => Stack(
      children: <Widget>[
        Center(
          child: FilledButton(
            onPressed: () => AleraToast.show(
              context,
              message:
                  'Could not push branch: rejected: non-fast-forward '
                  '(fetch first)',
              tone: .error,
            ),
            child: const Text('Show Error'),
          ),
        ),
        const AleraToastHost(
          clarifyError: _previewClarifier,
          clarifyingCaption: 'Clarifying with AI Assist…',
          clarifiedCaption: 'Clarified by AI Assist',
        ),
      ],
    );
