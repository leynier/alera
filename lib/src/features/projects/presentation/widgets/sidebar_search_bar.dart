import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:flutter/material.dart';

class const SidebarSearchBar({
  super.key,
  required final String initialQuery,
  required final ValueChanged<String> onChanged,
  required final FocusNode focusNode,
  final String hintText = 'Search projects',
}) extends StatefulWidget {
  @override
  State<SidebarSearchBar> createState() => _SidebarSearchBarState();
}

class _SidebarSearchBarState extends State<SidebarSearchBar> {
  late final TextEditingController _controller;
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
        selection: .collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space4,
        AleraTokens.space12,
        AleraTokens.space8,
      ),
      child: AleraSearchField(
        controller: _controller,
        focusNode: widget.focusNode,
        hintText: widget.hintText,
        dense: true,
        debounce: _debounceDuration,
        onChanged: widget.onChanged,
      ),
    );
  }
}
