part of 'mobile_codex_chat_screen.dart';

Future<String?> _showMobileReviewBranchPicker(
  BuildContext context, {
  required List<String> branches,
  required String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AleraTokens.surface,
  builder: (context) =>
      _MobileReviewBranchPicker(branches: branches, selected: selected),
);

class _MobileReviewBranchPicker extends StatefulWidget {
  const _MobileReviewBranchPicker({
    required this.branches,
    required this.selected,
  });

  final List<String> branches;
  final String? selected;

  @override
  State<_MobileReviewBranchPicker> createState() =>
      _MobileReviewBranchPickerState();
}

class _MobileReviewBranchPickerState extends State<_MobileReviewBranchPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final branches = widget.branches
        .where(
          (branch) => query.isEmpty || branch.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: AleraTokens.codexPickerHeightFactor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space20,
          AleraTokens.space4,
          AleraTokens.space20,
          AleraTokens.space16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Select Base Branch',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            TextField(
              key: const ValueKey<String>('mobile-codex-review-branch-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search Branches',
                prefixIcon: Icon(AleraIcons.search),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Expanded(
              child: branches.isEmpty
                  ? const Center(child: Text('No Branches Found'))
                  : ListView.builder(
                      itemCount: branches.length,
                      itemBuilder: (context, index) {
                        final branch = branches[index];
                        return ListTile(
                          minTileHeight: AleraTokens.minTapTarget,
                          selected: branch == widget.selected,
                          title: Text(
                            branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: branch == widget.selected
                              ? const Icon(
                                  AleraIcons.check,
                                  size: AleraTokens.space16,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(branch),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
