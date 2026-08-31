import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Canonical search input: search prefix, a clear button once text is present,
/// optional [debounce] before reporting changes, and escape-to-clear /
/// escape-to-unfocus. Pass [dense] for the compact sidebar variant.
class const AleraSearchField({
  super.key,
  final TextEditingController? controller,
  final FocusNode? focusNode,
  final String hintText = 'Search',
  final ValueChanged<String>? onChanged,
  final Duration? debounce,
  final bool dense = false,
  final bool autofocus = false,
}) extends StatefulWidget {
  @override
  State<AleraSearchField> createState() => _AleraSearchFieldState();
}

class _AleraSearchFieldState extends State<AleraSearchField> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _emit(String value) {
    final onChanged = widget.onChanged;
    if (onChanged == null) {
      return;
    }
    final debounce = widget.debounce;
    if (debounce == null) {
      onChanged(value);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(debounce, () => onChanged(value));
  }

  void _handleChange(String value) {
    setState(() {});
    _emit(value);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    widget.onChanged?.call('');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_controller.text.isNotEmpty) {
        _clear();
        return KeyEventResult.handled;
      }
      (widget.focusNode ?? node).unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    final clearButton = hasText
        ? IconButton(
            tooltip: 'Clear',
            icon: const Icon(
              AleraIcons.close,
              size: 12,
              color: AleraTokens.foregroundFaint,
            ),
            onPressed: _clear,
            visualDensity: .compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: AleraTextField.defaultDenseHeight,
            ),
          )
        : null;

    return Focus(
      onKeyEvent: _handleKey,
      child: AleraTextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        dense: widget.dense,
        hintText: widget.hintText,
        prefixIcon: AleraIcons.search,
        suffix: clearButton,
        onChanged: _handleChange,
      ),
    );
  }
}
