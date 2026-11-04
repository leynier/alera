import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_composer_menu.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

import 'alera_golden_harness.dart';

void _ignore(int _) {}

void main() {
  runAleraGoldenTests(() {
    goldenTest(
      'renders the composer menu states',
      fileName: 'composer_menu_states',
      constraints: const BoxConstraints(maxWidth: 780),
      builder: () => GoldenTestGroup(
        columns: 2,
        scenarioConstraints: const .tightFor(width: 340),
        children: <Widget>[
          GoldenTestScenario(
            name: 'Commands',
            child: const _Frame(
              height: 156,
              child: AleraComposerMenu(
                items: <AleraComposerMenuItem>[
                  AleraComposerMenuItem(
                    id: 'model',
                    label: '/model',
                    detail: 'Open the agent and model picker.',
                    leading: Icon(AleraIcons.agent, size: AleraTokens.iconMd),
                  ),
                  AleraComposerMenuItem(
                    id: 'plan',
                    label: '/plan',
                    detail: 'Plan before acting, from the next message.',
                    leading: Icon(AleraIcons.plan, size: AleraTokens.iconMd),
                  ),
                  AleraComposerMenuItem(
                    id: 'default',
                    label: '/default',
                    disabledReason: 'Default mode is already on.',
                    leading: Icon(AleraIcons.code, size: AleraTokens.iconMd),
                  ),
                ],
                activeIndex: 1,
                semanticsLabel: 'Commands',
                title: 'Commands',
                onPick: _ignore,
              ),
            ),
          ),
          GoldenTestScenario(
            name: 'Empty',
            child: const _Frame(
              height: 156,
              child: AleraComposerMenu(
                items: <AleraComposerMenuItem>[],
                activeIndex: 0,
                semanticsLabel: 'File Mentions',
                title: 'Files',
                emptyMessage: 'No matching files.',
                onPick: _ignore,
              ),
            ),
          ),
        ],
      ),
    );
  });
}

/// A fixed box: golden groups size scenarios by their intrinsic size, which
/// the menu's lazy list cannot report.
class const _Frame({required final double height, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 340,
    height: height,
    child: Align(alignment: .topCenter, child: child),
  );
}
