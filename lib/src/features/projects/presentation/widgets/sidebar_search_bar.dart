import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SidebarSearchBar extends StatefulWidget {
  const SidebarSearchBar({
    super.key,
    required this.initialQuery,
    required this.onChanged,
    required this.focusNode,
  });

  final String initialQuery;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;

  @override
  State<SidebarSearchBar> createState() => _SidebarSearchBarState();
}

class _SidebarSearchBarState extends State<SidebarSearchBar> {
  late final TextEditingController _controller;
  Timer? _debounce;
  static const Duration _debounceDuration = Duration(milliseconds: 80);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(SidebarSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialQuery,
        selection: TextSelection.collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleChange(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () => widget.onChanged(value));
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_controller.text.isNotEmpty) {
        _controller.clear();
        widget.onChanged('');
        return KeyEventResult.handled;
      }
      widget.focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space4,
        AleraTokens.space12,
        AleraTokens.space8,
      ),
      child: Focus(
        onKeyEvent: _handleKey,
        child: SizedBox(
          height: AleraTokens.space32 + AleraTokens.space8,
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            onChanged: _handleChange,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foreground,
            ),
            cursorColor: AleraTokens.foreground,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AleraTokens.surface,
              hintText: 'Search chats',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: AleraTokens.space8, right: 4),
                child: Icon(
                  Icons.search,
                  size: 14,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 24,
                minHeight: AleraTokens.space32 + AleraTokens.space8,
              ),
              suffixIcon: hasText
                  ? IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(
                        Icons.close,
                        size: 12,
                        color: AleraTokens.foregroundFaint,
                      ),
                      onPressed: () {
                        _controller.clear();
                        widget.onChanged('');
                      },
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: AleraTokens.space32 + AleraTokens.space8,
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 24,
                minHeight: AleraTokens.space32 + AleraTokens.space8,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                borderSide: const BorderSide(color: AleraTokens.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                borderSide: const BorderSide(color: AleraTokens.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                borderSide: const BorderSide(color: AleraTokens.border),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
