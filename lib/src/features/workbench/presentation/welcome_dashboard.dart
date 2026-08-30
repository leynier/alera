import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'welcome_dashboard_columns.dart';
part 'welcome_dashboard_cards.dart';

// coverage:ignore-line
class const WelcomeDashboard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workbenchControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AleraTokens.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AleraTokens.space32),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final content = [
                    if (isWide) ...[
                      Expanded(child: _LeftColumn(state: state)),
                      const SizedBox(width: AleraTokens.space32),
                      const Expanded(child: _RightColumn()),
                    ] else ...[
                      _LeftColumn(state: state),
                      const SizedBox(height: AleraTokens.space32),
                      const _RightColumn(),
                    ],
                  ];

                  return Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      _Header(theme: theme),
                      const SizedBox(height: AleraTokens.space32),
                      if (isWide)
                        Row(crossAxisAlignment: .start, children: content)
                      else
                        Column(crossAxisAlignment: .stretch, children: content),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
