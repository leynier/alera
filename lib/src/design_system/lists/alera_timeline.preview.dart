import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/lists/alera_timeline.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Run events', group: 'Timeline', size: Size(520, 320))
Widget aleraTimelinePreview() => AleraTimeline(
  entries: <AleraTimelineEntry>[
    AleraTimelineEntry(
      id: 'question',
      day: 'Today',
      time: '14:02',
      title: 'The worker asked which auth flow the CLI should use',
      detail: 'Waiting for an answer before continuing the login task.',
      open: true,
      actions: <Widget>[
        TextButton(onPressed: () {}, child: const Text('Resolve')),
      ],
    ),
    const AleraTimelineEntry(
      id: 'stage',
      day: 'Today',
      time: '13:58',
      title: 'Stage Foundation passed its gate',
    ),
    const AleraTimelineEntry(
      id: 'start',
      day: 'Yesterday',
      time: '18:40',
      title: 'Run started from the feature-delivery workflow',
      detail: 'Coordinator: default agent profile',
    ),
  ],
);

@AleraPreview(name: 'Empty', group: 'Timeline', size: Size(420, 120))
Widget aleraTimelineEmptyPreview() => const AleraTimeline(
  entries: <AleraTimelineEntry>[],
  emptyMessage: 'Nothing has happened in this run yet.',
);
