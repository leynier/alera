import 'package:flutter/material.dart';

/// Trailing toolbar or row actions sized to their intrinsic width so a
/// sibling [Expanded] can use the rest of the parent [Row].
///
/// Must be a direct child of that [Row]. If this widget receives a bounded
/// max width smaller than the actions, they scroll horizontally.
class const WorkbenchScrollableActions({
  super.key,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: .min, children: children),
    );
  }
}
