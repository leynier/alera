import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Pages loaded after the first one. The first page comes from a watched
/// provider that refreshes on runtime events; any refresh or filter change
/// drops the extra pages, so a list never mixes stale and fresh rows.
class InboxPageContinuation<T> {
  InboxPageContinuation(this._keyOf);

  final String Function(T item) _keyOf;
  final List<T> _items = <T>[];
  Object? _firstPage;
  String? _filter;
  int? _cursor;
  bool _continued = false;
  int _generation = 0;
  bool loading = false;
  Object? error;

  /// Called on every build with the current filter and first page.
  void sync(String filter, Object? firstPage) {
    if (filter == _filter && identical(firstPage, _firstPage)) return;
    _filter = filter;
    _firstPage = firstPage;
    _items.clear();
    _cursor = null;
    _continued = false;
    _generation++;
    loading = false;
    error = null;
  }

  /// The first page followed by the extra pages, without duplicates.
  List<T> merge(List<T> firstPage) {
    final seen = <String>{};
    return <T>[
      for (final item in <T>[...firstPage, ..._items])
        if (seen.add(_keyOf(item))) item,
    ];
  }

  /// Where the next page starts, or null when there is nothing more.
  int? cursorAfter(int? firstPageCursor) =>
      _continued ? _cursor : firstPageCursor;

  int get generation => _generation;

  /// Ignores a page that was requested before a refresh or filter change.
  void append(int generation, List<T> items, int? nextCursor) {
    if (generation != _generation) return;
    _items.addAll(items);
    _cursor = nextCursor;
    _continued = true;
  }
}

class const InboxLoadMoreButton({
  super.key,
  required final bool loading,
  required final VoidCallback onPressed,
  final String? error,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Column(
      spacing: AleraTokens.space4,
      children: <Widget>[
        if (error != null)
          Text(
            error!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.error),
          ),
        TextButton(
          key: const ValueKey<String>('inboxLoadMore'),
          onPressed: loading ? null : onPressed,
          child: Text(loading ? 'Loading...' : 'Load More'),
        ),
      ],
    ),
  );
}
