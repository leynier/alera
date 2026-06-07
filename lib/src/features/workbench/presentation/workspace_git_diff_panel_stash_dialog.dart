part of 'workspace_git_diff_panel.dart';

class _StashPickerDialog extends StatelessWidget {
  const _StashPickerDialog({required this.stashes});

  final List<GitStashEntry> stashes;

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Stash pop', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stashes.length,
                itemBuilder: (context, index) {
                  final stash = stashes[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      stash.reference,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      stash.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(stash),
                  );
                },
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
