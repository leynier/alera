import 'package:alera/src/features/terminal/application/terminal_session.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

class TerminalPanel extends StatelessWidget {
  const TerminalPanel({super.key, required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'terminal backend: ${session.backendType.name}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: TerminalView(
            session.terminal,
            autofocus: true,
            backgroundOpacity: 0.95,
          ),
        ),
      ],
    );
  }
}
