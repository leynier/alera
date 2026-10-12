import 'package:alera_automations/alera_automations.dart';

import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_section_body.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_entry_points.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/questions_section_body.dart';
import 'package:alera_mobile/src/features/runs/application/activity_providers.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/mobile_run_filters_sheet.dart';
import 'package:alera_mobile/src/features/runs/presentation/new_run_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/runs_section_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Activity at [section], optionally straight into one item.
Future<void> openActivity(
  BuildContext context, {
  required String hostId,
  required ActivitySection section,
  String? runId,
  String? gateId,
  String? threadId,
  AutomationScope? automationScope,
  String? automationId,
  String? automationRunId,
  bool startAutomationAuthoring = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => ActivityScreen(
      hostId: hostId,
      initialSection: section,
      initialRunId: runId,
      initialGateId: gateId,
      initialThreadId: threadId,
      automationScope: automationScope,
      initialAutomationId: automationId,
      initialAutomationRunId: automationRunId,
      startAutomationAuthoring: startAutomationAuthoring,
    ),
  ),
);

/// Runs, Questions and Automations of one host behind one segmented control.
/// The open part is kept per host, so coming back shows where the user was.
class const ActivityScreen({
  super.key,
  required final String hostId,
  final ActivitySection? initialSection,
  final String? initialRunId,
  final String? initialGateId,
  final String? initialThreadId,
  final AutomationScope? automationScope,
  final String? initialAutomationId,
  final String? initialAutomationRunId,
  final bool startAutomationAuthoring = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  /// The section asked for until the per-host controller has taken it, so
  /// the first frame never builds a part nobody asked to see.
  ActivitySection? _pending;

  String get _hostId => widget.hostId;

  @override
  void initState() {
    super.initState();
    _pending = widget.initialSection;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialRoute());
  }

  void _applyInitialRoute() {
    if (!mounted) return;
    if (_pending case final section?) {
      ref
          .read(mobileActivitySectionControllerProvider(_hostId).notifier)
          .select(section);
      setState(() => _pending = null);
    }
    if (widget.automationScope case final scope?) {
      ref
          .read(mobileAutomationListControllerProvider(_hostId).notifier)
          .setScope(scope);
    }
    if (widget.initialRunId case final runId?) {
      unawaited(openRun(context, _hostId, runId, gateId: widget.initialGateId));
    } else if (widget.initialThreadId case final threadId?) {
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                InboxThreadScreen(hostId: _hostId, threadId: threadId),
          ),
        ),
      );
    } else if (widget.initialAutomationId case final id?) {
      unawaited(
        openAutomationDetail(
          context,
          _hostId,
          id,
          runId: widget.initialAutomationRunId,
        ),
      );
    } else if (widget.startAutomationAuthoring) {
      unawaited(startAutomationAuthoring(context, ref, _hostId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = mobileActivitySectionControllerProvider(_hostId);
    final selected = ref.watch(controller);
    final section = _pending ?? selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: <Widget>[
          switch (section) {
            ActivitySection.runs => IconButton(
              tooltip: 'Filters',
              icon: const Icon(AleraIcons.filter),
              onPressed: () =>
                  unawaited(showMobileRunFilters(context, _hostId)),
            ),
            ActivitySection.questions => InboxPurgeMenu(hostId: _hostId),
            ActivitySection.automations => AutomationsSectionActions(
              hostId: _hostId,
            ),
          },
        ],
      ),
      floatingActionButton: _primaryAction(section),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space16,
                AleraTokens.space8,
                AleraTokens.space16,
                0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ActivitySection>(
                  segments: <ButtonSegment<ActivitySection>>[
                    for (final value in ActivitySection.values)
                      ButtonSegment(value: value, label: Text(value.label)),
                  ],
                  selected: <ActivitySection>{section},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() => _pending = null);
                    ref.read(controller.notifier).select(selection.first);
                  },
                ),
              ),
            ),
            Expanded(
              child: switch (section) {
                ActivitySection.runs => RunsSectionBody(hostId: _hostId),
                ActivitySection.questions => QuestionsSectionBody(
                  hostId: _hostId,
                ),
                ActivitySection.automations => AutomationsSectionBody(
                  hostId: _hostId,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget? _primaryAction(ActivitySection section) {
    switch (section) {
      case ActivitySection.runs:
        final client = ref.watch(mobileRunsClientProvider(_hostId));
        if (client.hasError && !client.hasValue) return null;
        return FloatingActionButton.extended(
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => NewRunScreen(hostId: _hostId),
              ),
            ),
          ),
          icon: const Icon(AleraIcons.add),
          label: const Text('New Run'),
        );
      case ActivitySection.questions:
        final inbox = ref.watch(mobileInboxClientProvider(_hostId));
        if (inbox.hasError && !inbox.hasValue) return null;
        return FloatingActionButton.extended(
          onPressed: () =>
              unawaited(askAgentAndOpenThread(context, ref, hostId: _hostId)),
          icon: const Icon(AleraIcons.send),
          label: const Text('Ask Agent'),
        );
      case ActivitySection.automations:
        if (automationsUnavailable(ref, _hostId)) return null;
        return FloatingActionButton.extended(
          onPressed: () =>
              unawaited(startAutomationAuthoring(context, ref, _hostId)),
          icon: const Icon(AleraIcons.add),
          label: const Text('New Automation'),
        );
    }
  }
}
