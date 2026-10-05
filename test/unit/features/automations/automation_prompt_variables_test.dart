import 'package:alera/src/features/automations/domain/automation_prompt_variables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an open {{ before the caret is a query', () {
    const text = 'Check {{work';
    final query = automationVariableQueryAt(text, text.length);
    expect(query?.start, 6);
    expect(query?.query, 'work');
    expect(automationVariableQueryAt('Check {{run.number}}', 20), isNull);
    expect(automationVariableQueryAt('Check {{a b', 11), isNull);
    expect(automationVariableQueryAt('No braces', 9), isNull);
  });

  test('matching ranks prefixes before other matches', () {
    expect(
      AutomationPromptVariable.matching('work').take(3),
      <AutomationPromptVariable>[.workspaceName, .workspacePath, .workspaceId],
    );
    expect(
      AutomationPromptVariable.matching('name'),
      contains(AutomationPromptVariable.projectName),
    );
    expect(
      AutomationPromptVariable.matching(''),
      AutomationPromptVariable.values,
    );
  });

  test('inserting completes an open query and its closing braces', () {
    final completed = insertAutomationVariable(
      'In {{wo}} now',
      7,
      7,
      AutomationPromptVariable.workspaceName,
    );
    expect(completed.text, 'In {{workspace.name}} now');
    expect(completed.caret, 'In {{workspace.name}}'.length);
  });

  test('inserting replaces the selection when no query is open', () {
    final replaced = insertAutomationVariable(
      'Run NAME today',
      4,
      8,
      AutomationPromptVariable.automationName,
    );
    expect(replaced.text, 'Run {{automation.name}} today');
    expect(replaced.caret, 'Run {{automation.name}}'.length);
  });

  test('segments mark known and unknown variables', () {
    final segments = automationTemplateSegments(
      'A {{ run.number }} and {{run.nmber}}.',
    );
    expect(
      segments.map((segment) => (segment.text, segment.known)),
      <(String, bool?)>[
        ('A ', null),
        ('{{ run.number }}', true),
        (' and ', null),
        ('{{run.nmber}}', false),
        ('.', null),
      ],
    );
    expect(
      unknownAutomationVariables('{{run.nmber}} {{run.nmber}} {{run.id}}'),
      <String>['{{run.nmber}}'],
    );
  });
}
