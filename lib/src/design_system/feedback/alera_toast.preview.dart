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
                  tone: AleraToastTone.success,
                ),
                child: const Text('Success'),
              ),
              FilledButton(
                onPressed: () => AleraToast.show(
                  context,
                  message: 'Something went wrong',
                  tone: AleraToastTone.error,
                ),
                child: const Text('Error'),
              ),
              FilledButton(
                onPressed: () => AleraToast.show(
                  context,
                  message: 'Heads up',
                  tone: AleraToastTone.info,
                ),
                child: const Text('Info'),
              ),
            ],
          ),
        ),
        const AleraToastHost(),
      ],
    );
