/// One task-list marker found in a review comment body.
class ReviewCommentTaskListItem {
  const ReviewCommentTaskListItem({
    required this.markerOffset,
    required this.checked,
  });

  /// The offset of the state character inside the square brackets.
  final int markerOffset;
  final bool checked;
}

final _reviewCommentTaskLine = RegExp(
  r'^[ \t]*(?:>[ \t]*)*(?:(?:(?:-|\*|\+)[ \t]+)|(?:[0-9]+[.)][ \t]+))?\[([ xX])\][ \t]+\S.*$',
);
final _reviewCommentFence = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})');

/// Finds task items in display order while skipping fenced code blocks.
List<ReviewCommentTaskListItem> findReviewCommentTaskListItems(String body) {
  final items = <ReviewCommentTaskListItem>[];
  final lines = body.split('\n');
  String? fenceCharacter;
  var fenceLength = 0;
  var offset = 0;

  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines[index];
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    final fence = _reviewCommentFence.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      final character = marker.substring(0, 1);
      final rest = line.substring(fence.end).trim();
      if (fenceCharacter == null) {
        fenceCharacter = character;
        fenceLength = marker.length;
      } else if (character == fenceCharacter &&
          marker.length >= fenceLength &&
          rest.isEmpty) {
        fenceCharacter = null;
        fenceLength = 0;
      }
    } else if (fenceCharacter == null) {
      final match = _reviewCommentTaskLine.firstMatch(line);
      if (match != null) {
        final stateOffset = line.indexOf('[', match.start) + 1;
        items.add(
          ReviewCommentTaskListItem(
            markerOffset: offset + stateOffset,
            checked: match.group(1)!.toLowerCase() == 'x',
          ),
        );
      }
    }
    offset += rawLine.length;
    if (index < lines.length - 1) {
      offset++;
    }
  }
  return items;
}

/// Toggles one task item and preserves every other byte of [body].
String? toggleReviewCommentTaskListItem(String body, int itemIndex) {
  final items = findReviewCommentTaskListItems(body);
  if (itemIndex < 0 || itemIndex >= items.length) {
    return null;
  }
  final item = items[itemIndex];
  final replacement = item.checked ? ' ' : 'x';
  return body.replaceRange(
    item.markerOffset,
    item.markerOffset + 1,
    replacement,
  );
}
