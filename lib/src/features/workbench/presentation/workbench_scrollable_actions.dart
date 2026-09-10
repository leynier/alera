import 'package:flutter/material.dart';

/// Trailing toolbar or row actions that scroll instead of overflowing a
/// narrow parent [Row]. Must be a direct child of that [Row].
class const WorkbenchScrollableActions({
  super.key,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Align(
        alignment: .centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(mainAxisSize: .min, children: children),
        ),
      ),
    );
  }
}
