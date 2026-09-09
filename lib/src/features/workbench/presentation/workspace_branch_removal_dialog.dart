import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

Future<bool?> showWorkspaceBranchRemovalDialog(
  BuildContext context,
  String? branch,
) => showDialog<bool>(
  context: context,
  builder: (context) => AleraDialog(
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep or Delete Branch?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            branch == null || branch.isEmpty
                ? 'The workspace branch is unknown. Keep its branches when removing the workspace.'
                : 'Branch safety may have changed since this workspace was created. Keep "$branch" unless you want Alera to attempt safe deletion. Unmerged or protected branches will be retained.',
          ),
          const SizedBox(height: AleraTokens.space20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AleraTokens.space8),
              TextButton(
                onPressed: branch == null || branch.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Delete Branch'),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Branch'),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
