import 'package:flutter/services.dart';

const _catalogTokenStartKey = '_aleraCatalogTokenStart';
const _catalogTokenEndKey = '_aleraCatalogTokenEnd';

Map<String, Object?> mobileCodexTrackCatalogSelection(
  Map<String, Object?> selection, {
  required int tokenStart,
}) {
  final name = selection['name']?.toString().trim() ?? '';
  if (name.isEmpty) return selection;
  return <String, Object?>{
    ...selection,
    _catalogTokenStartKey: tokenStart,
    _catalogTokenEndKey: tokenStart + name.length + 1,
  };
}

List<Map<String, Object?>> mobileCodexRebaseCatalogSelections(
  TextEditingValue previous,
  TextEditingValue next,
  Iterable<Map<String, Object?>> selections,
) {
  if (previous.text == next.text) {
    return mobileCodexActiveCatalogSelections(next.text, selections);
  }
  final edit = _catalogTextEdit(previous, next);
  final delta = edit.newEnd - edit.oldEnd;
  final rebased = <Map<String, Object?>>[];
  for (final selection in selections) {
    final start = selection[_catalogTokenStartKey];
    final end = selection[_catalogTokenEndKey];
    if (start is! int || end is! int || start < 0 || end < start) {
      rebased.add(selection);
      continue;
    }
    if (end <= edit.oldStart) {
      rebased.add(selection);
    } else if (start >= edit.oldEnd) {
      rebased.add(<String, Object?>{
        ...selection,
        _catalogTokenStartKey: start + delta,
        _catalogTokenEndKey: end + delta,
      });
    }
  }
  return mobileCodexActiveCatalogSelections(next.text, rebased);
}

List<Map<String, Object?>> mobileCodexActiveCatalogSelections(
  String text,
  Iterable<Map<String, Object?>> selections,
) {
  final result = <Map<String, Object?>>[];
  final claimedStarts = <int>{};
  final untracked = <Map<String, Object?>>[];
  for (final selection in selections) {
    final name = selection['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final start = selection[_catalogTokenStartKey];
    final end = selection[_catalogTokenEndKey];
    if (start is! int || end is! int) {
      untracked.add(selection);
      continue;
    }
    if (_catalogTokenMatches(text, name.trim(), start, end)) {
      result.add(selection);
      claimedStarts.add(start);
    }
  }
  for (final selection in untracked) {
    final name = selection['name']!.toString().trim();
    final matches = _catalogTokenRangesForName(
      text,
      name,
    ).where((candidate) => !claimedStarts.contains(candidate.start));
    if (matches.isEmpty) continue;
    final match = matches.first;
    result.add(
      mobileCodexTrackCatalogSelection(selection, tokenStart: match.start),
    );
    claimedStarts.add(match.start);
  }
  return result;
}

Map<String, Object?> mobileCodexCatalogWireSelection(
  Map<String, Object?> selection,
) => <String, Object?>{
  for (final entry in selection.entries)
    if (entry.key != _catalogTokenStartKey && entry.key != _catalogTokenEndKey)
      entry.key: entry.value,
};

List<Map<String, Object?>> mobileCodexShiftCatalogSelections(
  Iterable<Map<String, Object?>> selections,
  int offset,
) => <Map<String, Object?>>[
  for (final selection in selections)
    if (selection[_catalogTokenStartKey] case final int start)
      <String, Object?>{
        ...selection,
        _catalogTokenStartKey: start + offset,
        if (selection[_catalogTokenEndKey] case final int end)
          _catalogTokenEndKey: end + offset,
      }
    else
      selection,
];

List<Map<String, Object?>> mobileCodexTrimCatalogSelections(
  String text,
  Iterable<Map<String, Object?>> selections,
) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const <Map<String, Object?>>[];
  final leadingOffset = text.indexOf(trimmed);
  return mobileCodexActiveCatalogSelections(
    trimmed,
    mobileCodexShiftCatalogSelections(selections, -leadingOffset),
  );
}

bool _catalogTokenMatches(String text, String name, int start, int end) {
  final token = '\$$name';
  return start >= 0 &&
      end == start + token.length &&
      end <= text.length &&
      text.substring(start, end) == token &&
      (start == 0 || _isCatalogWhitespace(text.codeUnitAt(start - 1))) &&
      (end == text.length || _isCatalogWhitespace(text.codeUnitAt(end)));
}

Iterable<({int start, int end})> _catalogTokenRangesForName(
  String text,
  String name,
) {
  final pattern = RegExp('(?:^|\\s)(\\\$${RegExp.escape(name)})(?=\\s|\$)');
  return pattern.allMatches(text).map((match) {
    final token = match.group(1)!;
    final start = match.start + match.group(0)!.indexOf(token);
    return (start: start, end: start + token.length);
  });
}

bool _isCatalogWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

({int oldStart, int oldEnd, int newEnd}) _catalogTextEdit(
  TextEditingValue previous,
  TextEditingValue next,
) {
  final oldSelection = previous.selection;
  final nextSelection = next.selection;
  if (oldSelection.isValid &&
      !oldSelection.isCollapsed &&
      nextSelection.isValid &&
      nextSelection.isCollapsed) {
    final oldStart = oldSelection.start;
    final oldEnd = oldSelection.end;
    final inserted =
        next.text.length - (previous.text.length - (oldEnd - oldStart));
    if (inserted >= 0 && nextSelection.extentOffset == oldStart + inserted) {
      return (oldStart: oldStart, oldEnd: oldEnd, newEnd: oldStart + inserted);
    }
  }
  if (oldSelection.isValid &&
      oldSelection.isCollapsed &&
      nextSelection.isValid &&
      nextSelection.isCollapsed) {
    final oldCaret = oldSelection.extentOffset;
    final nextCaret = nextSelection.extentOffset;
    final lengthDelta = next.text.length - previous.text.length;
    if (lengthDelta > 0 && nextCaret == oldCaret + lengthDelta) {
      return (
        oldStart: oldCaret,
        oldEnd: oldCaret,
        newEnd: oldCaret + lengthDelta,
      );
    }
    if (lengthDelta < 0) {
      final removed = -lengthDelta;
      if (nextCaret == oldCaret - removed) {
        return (oldStart: nextCaret, oldEnd: oldCaret, newEnd: nextCaret);
      }
      if (nextCaret == oldCaret) {
        return (
          oldStart: oldCaret,
          oldEnd: oldCaret + removed,
          newEnd: oldCaret,
        );
      }
    }
  }
  var prefix = 0;
  final shortest = previous.text.length < next.text.length
      ? previous.text.length
      : next.text.length;
  while (prefix < shortest &&
      previous.text.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < previous.text.length - prefix &&
      suffix < next.text.length - prefix &&
      previous.text.codeUnitAt(previous.text.length - suffix - 1) ==
          next.text.codeUnitAt(next.text.length - suffix - 1)) {
    suffix++;
  }
  return (
    oldStart: prefix,
    oldEnd: previous.text.length - suffix,
    newEnd: next.text.length - suffix,
  );
}
