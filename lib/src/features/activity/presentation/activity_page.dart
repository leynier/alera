import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_header.dart';
import 'package:alera/src/features/activity/presentation/activity_rail.dart';
import 'package:alera/src/features/automations/presentation/automations_section.dart';
import 'package:alera/src/features/inbox/presentation/questions_section.dart';
import 'package:alera/src/features/runs/presentation/runs_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs, questions and automations across projects, shown over the retained
/// workbench. Closing it hands focus back to the active pane through the
/// shell, so this page never selects a workspace on its own.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'Activity');

  @override
  void initState() {
    super.initState();
    // The pane that held focus is hidden, not unmounted, so autofocus alone
    // can lose to it; claim the scope once laid out unless something inside
    // already has focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(
      activityNavigationProvider.select((value) => value.section),
    );
    final body = switch (section) {
      ActivitySection.runs => const RunsSection(),
      ActivitySection.questions => const QuestionsSection(),
      ActivitySection.automations => const AutomationsSection(),
    };
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: _ActivityDismissAction(
            ref.read(activityNavigationProvider.notifier).close,
          ),
        },
        child: FocusScope(
          node: _scope,
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                const ActivityHeader(),
                const SizedBox(height: AleraTokens.space12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final compact =
                          constraints.maxWidth <
                          AleraTokens.wideContentBreakpoint * scale;
                      return Row(
                        crossAxisAlignment: .stretch,
                        children: <Widget>[
                          ActivityRail(compact: compact),
                          const SizedBox(width: AleraTokens.space12),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey<ActivitySection>(section),
                              child: body,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Esc closes Activity, except that a focused text field with content takes
/// the first Esc to clear itself, so a field cannot close the page mid-edit.
class _ActivityDismissAction extends Action<DismissIntent> {
  _ActivityDismissAction(this.onClose);

  final VoidCallback onClose;

  @override
  Object? invoke(DismissIntent intent) {
    final field = primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (field != null &&
        !field.widget.readOnly &&
        field.textEditingValue.text.isNotEmpty) {
      field.userUpdateTextEditingValue(
        TextEditingValue.empty,
        SelectionChangedCause.keyboard,
      );
      return null;
    }
    onClose();
    return null;
  }
}
