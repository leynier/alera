part of 'workspace_editor_surface.dart';

extension _WorkspaceEditorTextActions on _WorkspaceEditorSurfaceState {
  void _captureEditorPointerDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      _lastSecondaryTapGlobalPosition = event.position;
    }
  }

  List<code_forge.CustomContextMenu>? _editorTextActionMenuItems(
    BuildContext context,
  ) {
    final scope = AleraTextActionsScope.maybeOf(context);
    if (scope?.enabled != true ||
        !workspaceEditorHasTextActionSelection(
          text: _controller.text,
          selection: _controller.selection,
        )) {
      return null;
    }
    return <code_forge.CustomContextMenu>[
      code_forge.CustomContextMenu(
        label: 'Text Actions',
        description: '',
        onPress: () => _openEditorTextActions(context, scope!),
      ),
    ];
  }

  void _openEditorTextActions(
    BuildContext context,
    AleraTextActionsScope scope,
  ) {
    final anchor =
        _lastSecondaryTapGlobalPosition ?? _editorCenterGlobalPosition(context);
    scope.open(context, _editorTextActionTarget(), anchor);
  }

  Offset _editorCenterGlobalPosition(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.localToGlobal(renderObject.size.center(Offset.zero));
    }
    return Offset.zero;
  }

  AleraTextActionTarget _editorTextActionTarget() {
    return AleraTextActionTarget(
      identity: _controller,
      readValue: _editorTextEditingValue,
      isAvailable: () => mounted && !_loading && _loadError == null,
      applyReplacement: (captured, replacement) {
        if (!mounted || _editorTextEditingValue() != captured) {
          return false;
        }
        final selection = captured.selection;
        _controller.replaceRange(selection.start, selection.end, replacement);
        return true;
      },
    );
  }

  TextEditingValue _editorTextEditingValue() {
    return TextEditingValue(
      text: _controller.text,
      selection: _controller.selection,
    );
  }

  code_forge.SuggestionStyle _editorOverlayStyle(BuildContext context) {
    return code_forge.SuggestionStyle(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      backgroundColor: AleraTokens.surface,
      focusColor: AleraTokens.surfaceElevated,
      hoverColor: AleraTokens.surfaceElevated,
      splashColor: Colors.transparent,
      textStyle: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: AleraTokens.foreground),
      itemHeight: AleraTokens.space32 + AleraTokens.space4,
    );
  }
}

@visibleForTesting
bool workspaceEditorHasTextActionSelection({
  required String text,
  required TextSelection selection,
}) {
  return selection.isValid &&
      !selection.isCollapsed &&
      selection.start >= 0 &&
      selection.end <= text.length &&
      text.substring(selection.start, selection.end).isNotEmpty;
}
