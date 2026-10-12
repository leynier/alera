import 'package:alera_automations/alera_automations.dart';

String mobileAutomationScheduleLine(AutomationRecord automation) {
  if (automation.isCompleted) return 'Completed';
  final description = automationScheduleDescription(automation.schedule);
  final next = automation.nextRunAt;
  if (next == null || automation.state != 'active') return description;
  return '$description · next ${automationRelativeTime(next)}';
}

/// "Succeeded 5m ago" for the last run of a definition.
String mobileAutomationLastRunLabel(AutomationLastRun run) {
  final status = automationRunStatusLabel(
    AutomationRunRecord(
      id: run.id,
      automationId: '',
      number: 0,
      status: run.status,
      trigger: '',
      summary: run.summary,
      error: null,
      scheduledAt: null,
      finishedAt: run.finishedAt,
    ),
  ).label;
  final finished = run.finishedAt;
  return finished == null
      ? status
      : '$status ${automationRelativeTime(finished)}';
}
