import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_composer_suggestions.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

Widget _command(IconData icon) =>
    Icon(icon, size: AleraTokens.iconMd, color: AleraTokens.foregroundMuted);

@AleraPreview(name: 'Commands', group: 'Composer Suggestions')
Widget aleraComposerSuggestionsCommandsPreview() => Padding(
  padding: AleraTokens.pagePadding,
  child: AleraComposerSuggestions(
    title: 'Commands',
    items: <AleraComposerSuggestion>[
      AleraComposerSuggestion(
        id: 'model',
        label: '/model',
        detail: 'Open the agent and model picker.',
        leading: _command(AleraIcons.agent),
      ),
      AleraComposerSuggestion(
        id: 'usage',
        label: '/usage',
        disabledReason: 'The agent has not reported usage yet.',
        leading: _command(AleraIcons.quota),
      ),
      AleraComposerSuggestion(
        id: 'compact',
        label: '/compact',
        detail: 'Clear history but keep a summary in context',
        leading: _command(AleraIcons.agentCommand),
      ),
    ],
    onPick: (_) {},
    onDismiss: () {},
  ),
);

@AleraPreview(name: 'Files', group: 'Composer Suggestions')
Widget aleraComposerSuggestionsFilesPreview() => Padding(
  padding: AleraTokens.pagePadding,
  child: AleraComposerSuggestions(
    title: 'Files',
    loading: true,
    items: <AleraComposerSuggestion>[
      for (final path in const <String>[
        'lib/main.dart',
        'lib/src/app/theme/alera_tokens.dart',
        'pubspec.yaml',
      ])
        AleraComposerSuggestion(
          id: path,
          label: path.split('/').last,
          detail: path.contains('/')
              ? path.substring(0, path.lastIndexOf('/'))
              : null,
          leading: AleraFileIcon(
            pathOrName: path,
            kind: .file,
            size: AleraTokens.iconMd,
          ),
        ),
    ],
    onPick: (_) {},
    onDismiss: () {},
  ),
);

@AleraPreview(name: 'Empty', group: 'Composer Suggestions')
Widget aleraComposerSuggestionsEmptyPreview() => Padding(
  padding: AleraTokens.pagePadding,
  child: AleraComposerSuggestions(
    title: 'Files',
    items: const <AleraComposerSuggestion>[],
    emptyMessage: 'No matching files.',
    onPick: (_) {},
    onDismiss: () {},
  ),
);
