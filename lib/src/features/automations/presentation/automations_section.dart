import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_view.dart';
import 'package:alera/src/features/automations/presentation/catalog/automation_catalog_bar.dart';
import 'package:alera/src/features/automations/presentation/catalog/automation_catalog_list.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens New Automation from the scope the catalog is looking at.
Future<void> startAutomationAuthoringFromSection(
  BuildContext context,
  WidgetRef ref,
) async {
  final scope = ref.read(activityNavigationProvider).automations.scope;
  final names = ref.read(automationWorkbenchContextProvider);
  await showAutomationComposerDialog(
    context,
    ref,
    request: _requestForScope(scope, names),
  );
}

/// The Automations section of Activity.
class AutomationsSection extends ConsumerStatefulWidget {
  const AutomationsSection({super.key});

  @override
  ConsumerState<AutomationsSection> createState() => _AutomationsSectionState();
}

class _AutomationsSectionState extends ConsumerState<AutomationsSection> {
  int _handledAuthoring = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartAuthoring());
  }

  void _maybeStartAuthoring() {
    if (!mounted) return;
    final location = ref.read(activityNavigationProvider).automations;
    final request = location.authoring;
    if (request == null || location.authoringSequence == _handledAuthoring) {
      return;
    }
    _handledAuthoring = location.authoringSequence;
    ref.read(activityNavigationProvider.notifier).consumeAuthoring();
    unawaited(showAutomationComposerDialog(context, ref, request: request));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      activityNavigationProvider.select(
        (value) => value.automations.authoringSequence,
      ),
      (_, _) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeStartAuthoring(),
      ),
    );
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.automations),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    final catalog = ref.watch(automationCatalogProvider);
    final names = ref.watch(automationWorkbenchContextProvider);
    final automations = catalog.value ?? const <AutomationRecord>[];
    final selected = automations
        .where((item) => item.id == location.selectedId)
        .firstOrNull;
    final attention =
        automationBucketCounts(
          automations,
          location.scope,
        )[AutomationBucket.needsAttention] ??
        0;
    final master = AutomationCatalogList(
      catalog: catalog,
      location: location,
      names: names,
    );
    Widget detail({VoidCallback? onBack}) => selected == null
        ? AleraEmptyState(
            icon: AleraIcons.schedule,
            title: location.selectedId == null
                ? 'Select An Automation'
                : 'Automation Unavailable',
            message: location.selectedId == null
                ? 'Inspect schedules, destinations, runs and recovery. Opening this page does not change your workspace.'
                : 'It may have been deleted. Choose another automation.',
          )
        : AutomationDetailView(
            key: ValueKey<String>(selected.id),
            automation: selected,
            selectedRunId: location.selectedRunId,
            onBack: onBack,
          );
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _RuntimeAvailabilityNotice(unreachable: catalog.hasError),
          if (attention > 0 &&
              location.filters.bucket != AutomationBucket.needsAttention)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: AleraInlineNotice(
                tone: .warning,
                message: attention == 1
                    ? '1 automation needs attention.'
                    : '$attention automations need attention.',
                child: TextButton(
                  onPressed: () => navigation.setAutomationFilters(
                    const AutomationCatalogFilters(
                      bucket: AutomationBucket.needsAttention,
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          const SizedBox(height: AleraTokens.space8),
          AutomationCatalogBar(
            automations: automations,
            location: location,
            names: names,
          ),
          const SizedBox(height: AleraTokens.space8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                if (constraints.maxWidth <
                    AleraTokens.wideContentBreakpoint * scale) {
                  return selected == null
                      ? master
                      : detail(onBack: () => navigation.selectAutomation(null));
                }
                return AleraMasterDetail(
                  masterTitle: 'Automations',
                  masterWidth: AleraTokens.masterDetailMaxWidth,
                  masterMaxWidth: AleraTokens.masterDetailMaxWidth,
                  master: master,
                  detail: detail(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

AutomationAuthoringRequest _requestForScope(
  AutomationScope scope,
  AutomationWorkbenchContext names,
) => switch (scope.kind) {
  AutomationScopeKind.workspace => AutomationAuthoringRequest(
    originWorkspaceId: scope.id,
  ),
  AutomationScopeKind.project => AutomationAuthoringRequest(
    projectId: scope.id,
  ),
  AutomationScopeKind.section => AutomationAuthoringRequest(
    sectionId: scope.id,
    projectId: _onlyProjectInSection(scope.id, names),
  ),
  AutomationScopeKind.all => const AutomationAuthoringRequest(),
};

String? _onlyProjectInSection(
  String? sectionId,
  AutomationWorkbenchContext names,
) {
  if (sectionId == null) return null;
  final projects = names
      .workspacesInSection(sectionId)
      .map((workspace) => workspace.projectId)
      .toSet();
  return projects.length == 1 ? projects.single : null;
}

/// The runtime owns schedules. Nothing here starts it or changes autostart.
class const _RuntimeAvailabilityNotice({required final bool unreachable})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (unreachable) {
      return const AleraInlineNotice(
        tone: .warning,
        message: 'The Alera runtime is not reachable. Automations run only while Alera is open or a runtime started with alera runtime start is running.',
      );
    }
    return Text(
      'Automations run while the Alera runtime is running. Interrupted runs recover when it starts again.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}
