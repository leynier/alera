import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_segmented_choice.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Two options',
  group: 'Segmented choice',
  size: Size(520, 140),
)
Widget aleraSegmentedChoicePreview() => AleraSegmentedChoice<String>(
  label: 'Deliver',
  selected: 'now',
  onChanged: (_) {},
  options: const <AleraSegmentedChoiceOption<String>>[
    AleraSegmentedChoiceOption<String>(
      value: 'now',
      label: 'Now',
      helper: "The question is pasted into the agent's terminal right away.",
    ),
    AleraSegmentedChoiceOption<String>(
      value: 'turnEnd',
      label: 'When the Agent Finishes Its Turn',
      helper: 'The agent receives the question when it finishes its turn.',
    ),
  ],
);

@AleraPreview(
  name: 'Disabled option',
  group: 'Segmented choice',
  size: Size(520, 160),
)
Widget aleraSegmentedChoiceDisabledPreview() => AleraSegmentedChoice<String>(
  label: 'Deliver',
  selected: 'turnEnd',
  onChanged: (_) {},
  options: const <AleraSegmentedChoiceOption<String>>[
    AleraSegmentedChoiceOption<String>(
      value: 'now',
      label: 'Now',
      helper: "The question is pasted into the agent's terminal right away.",
      enabled: false,
      disabledReason: 'This agent cannot take input while it works.',
    ),
    AleraSegmentedChoiceOption<String>(
      value: 'turnEnd',
      label: 'When the Agent Finishes Its Turn',
      helper: 'The agent receives the question when it finishes its turn.',
    ),
  ],
);
