// The automation domain is a copy of the desktop one in
// lib/src/features/automations/domain: alera_mobile has no dependency on the
// root package. Keep both copies in sync.

/// A `{{key}}` the runtime fills when it renders a run prompt. Keep in sync
/// with `KNOWN_VARIABLES` in `rust/alera-core/src/runtime/automation_templates.rs`:
/// the runtime rejects a prompt that names any other variable.
enum AutomationPromptVariable(
  final String key,
  final String label,
  final String description,
) {
  automationName(
    'automation.name',
    'Automation Name',
    'The name of this automation.',
  ),
  runNumber('run.number', 'Run Number', 'The sequence number of this run.'),
  runScheduledAt(
    'run.scheduledAt',
    'Scheduled Time',
    'When this run was scheduled to start.',
  ),
  workspaceName(
    'workspace.name',
    'Workspace Name',
    'The workspace the run starts in.',
  ),
  workspacePath(
    'workspace.path',
    'Workspace Path',
    'The folder the agent works in.',
  ),
  projectName('project.name', 'Project Name', 'The project of the workspace.'),
  automationSlug(
    'automation.slug',
    'Automation Slug',
    'The stable short name used in branches and workspace names.',
  ),
  runId('run.id', 'Run Id', 'The unique id of this run.'),
  automationId('automation.id', 'Automation Id', 'The id of this automation.'),
  workspaceId('workspace.id', 'Workspace Id', 'The id of the workspace.'),
  projectId('project.id', 'Project Id', 'The id of the project.');

  String get token => '{{$key}}';

  static AutomationPromptVariable? byKey(String key) {
    for (final variable in values) {
      if (variable.key == key) return variable;
    }
    return null;
  }

  /// The variables whose key or label contain [query], best matches first.
  static List<AutomationPromptVariable> matching(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return values;
    final prefix = <AutomationPromptVariable>[];
    final contains = <AutomationPromptVariable>[];
    for (final variable in values) {
      final key = variable.key.toLowerCase();
      final label = variable.label.toLowerCase();
      if (key.startsWith(needle) || label.startsWith(needle)) {
        prefix.add(variable);
      } else if (key.contains(needle) || label.contains(needle)) {
        contains.add(variable);
      }
    }
    return <AutomationPromptVariable>[...prefix, ...contains];
  }
}

/// An unfinished `{{partial` right before the caret, which the editor offers
/// to complete.
class const AutomationVariableQuery({
  required final int start,
  required final String query,
});

final RegExp _partialVariable = RegExp(r'^[A-Za-z.]*$');

AutomationVariableQuery? automationVariableQueryAt(String text, int caret) {
  if (caret < 2 || caret > text.length) return null;
  final open = text.lastIndexOf('{{', caret - 2);
  if (open < 0) return null;
  final query = text.substring(open + 2, caret);
  if (!_partialVariable.hasMatch(query)) return null;
  return AutomationVariableQuery(start: open, query: query);
}

/// Inserts [variable] at the caret: it completes an open `{{partial` there,
/// otherwise it replaces the selection. Returns the new text and caret.
({String text, int caret}) insertAutomationVariable(
  String text,
  int selectionStart,
  int selectionEnd,
  AutomationPromptVariable variable,
) {
  var start = selectionStart.clamp(0, text.length);
  var end = selectionEnd.clamp(start, text.length);
  if (start == end) {
    if (automationVariableQueryAt(text, start) case final query?) {
      start = query.start;
      if (text.startsWith('}}', end)) end += 2;
    }
  }
  final token = variable.token;
  return (
    text: text.replaceRange(start, end, token),
    caret: start + token.length,
  );
}

/// A run of prompt text: plain, a known variable or an unknown one.
class const AutomationTemplateSegment({
  required final String text,
  final bool? known,
});

final RegExp _variableToken = RegExp(r'\{\{\s*([^{}]*?)\s*\}\}');

List<AutomationTemplateSegment> automationTemplateSegments(String text) {
  final segments = <AutomationTemplateSegment>[];
  var cursor = 0;
  for (final match in _variableToken.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(
        AutomationTemplateSegment(text: text.substring(cursor, match.start)),
      );
    }
    segments.add(
      AutomationTemplateSegment(
        text: match.group(0)!,
        known: AutomationPromptVariable.byKey(match.group(1)!) != null,
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    segments.add(AutomationTemplateSegment(text: text.substring(cursor)));
  }
  return segments;
}

List<String> unknownAutomationVariables(String text) => <String>{
  for (final match in _variableToken.allMatches(text))
    if (AutomationPromptVariable.byKey(match.group(1)!) == null)
      match.group(0)!,
}.toList();
