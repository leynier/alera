part of 'workspace_git_diff_panel.dart';

class _GitHistoryGraph extends StatelessWidget {
  const _GitHistoryGraph({required this.viewModel});

  final GitHistoryItemViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final width =
        11.0 *
        ([
              viewModel.inputSwimlanes.length,
              viewModel.outputSwimlanes.length,
              1,
            ].reduce((a, b) => a > b ? a : b) +
            1);
    return SizedBox(
      width: width,
      height: 24,
      child: CustomPaint(painter: _GitHistoryGraphPainter(viewModel)),
    );
  }
}

class _GitHistoryGraphPainter extends CustomPainter {
  const _GitHistoryGraphPainter(this.viewModel);

  static const double laneHeight = 24;
  static const double laneWidth = 11;
  static const double nodeY = laneHeight / 2;
  static const double circleRadius = 3.5;

  final GitHistoryItemViewModel viewModel;

  @override
  void paint(Canvas canvas, Size size) {
    final item = viewModel.historyItem;
    final input = viewModel.inputSwimlanes;
    final output = viewModel.outputSwimlanes;
    final inputIndex = input.indexWhere((node) => node.id == item.id);
    final circleIndex = gitHistoryItemLaneIndex(viewModel);
    final circleColor = circleIndex < output.length
        ? output[circleIndex].color
        : circleIndex < input.length
        ? input[circleIndex].color
        : gitHistoryRefColor;
    var outputIndex = 0;

    for (var index = 0; index < input.length; index += 1) {
      final color = input[index].color;
      if (input[index].id == item.id) {
        if (index != circleIndex) {
          _drawPath(
            canvas,
            color,
            Path()
              ..moveTo(laneWidth * (index + 1), 0)
              ..quadraticBezierTo(
                laneWidth * index,
                nodeY,
                laneWidth * (circleIndex + 1),
                nodeY,
              ),
          );
        } else {
          outputIndex += 1;
        }
        continue;
      }
      if (outputIndex < output.length &&
          input[index].id == output[outputIndex].id) {
        final path = Path()..moveTo(laneWidth * (index + 1), 0);
        if (index == outputIndex) {
          path.lineTo(laneWidth * (index + 1), laneHeight);
        } else {
          path
            ..lineTo(laneWidth * (index + 1), 6)
            ..quadraticBezierTo(
              laneWidth * (index + 1),
              nodeY,
              laneWidth * (outputIndex + 1),
              nodeY,
            )
            ..lineTo(laneWidth * (outputIndex + 1), laneHeight);
        }
        _drawPath(canvas, color, path);
        outputIndex += 1;
      }
    }

    for (var index = 1; index < item.parentIds.length; index += 1) {
      final parentIndex = gitHistoryMergeParentLaneIndex(
        viewModel,
        item.parentIds[index],
      );
      if (parentIndex == -1) {
        continue;
      }
      _drawPath(
        canvas,
        output[parentIndex].color,
        Path()
          ..moveTo(laneWidth * (parentIndex + 1), nodeY)
          ..lineTo(laneWidth * (circleIndex + 1), nodeY)
          ..moveTo(laneWidth * (parentIndex + 1), nodeY)
          ..quadraticBezierTo(
            laneWidth * (parentIndex + 1),
            laneHeight,
            laneWidth * (parentIndex + 1),
            laneHeight,
          ),
      );
    }

    if (inputIndex != -1) {
      _drawPath(
        canvas,
        input[inputIndex].color,
        Path()
          ..moveTo(laneWidth * (circleIndex + 1), 0)
          ..lineTo(laneWidth * (circleIndex + 1), nodeY),
      );
    }
    if (item.parentIds.isNotEmpty) {
      _drawPath(
        canvas,
        circleColor,
        Path()
          ..moveTo(laneWidth * (circleIndex + 1), nodeY)
          ..lineTo(laneWidth * (circleIndex + 1), laneHeight),
      );
    }

    _drawNode(canvas, circleIndex, circleColor);
  }

  void _drawPath(Canvas canvas, GitHistoryGraphColorId color, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _graphColor(color) ?? AleraTokens.foregroundMuted
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawNode(Canvas canvas, int circleIndex, GitHistoryGraphColorId color) {
    final center = Offset(laneWidth * (circleIndex + 1), nodeY);
    final paint = Paint()..color = _graphColor(color) ?? AleraTokens.foreground;
    final boundary =
        viewModel.kind == GitHistoryItemViewModelKind.incomingChanges ||
        viewModel.kind == GitHistoryItemViewModelKind.outgoingChanges;
    if (viewModel.kind == GitHistoryItemViewModelKind.head || boundary) {
      canvas.drawCircle(center, circleRadius + 3, paint);
      canvas.drawCircle(center, circleRadius, Paint()..color = AleraTokens.bg);
      if (boundary) {
        canvas.drawCircle(
          center,
          circleRadius + 1,
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      return;
    }
    if (viewModel.historyItem.parentIds.length > 1) {
      canvas.drawCircle(center, circleRadius + 1, paint);
      canvas.drawCircle(
        center,
        circleRadius - 1.5,
        Paint()..color = AleraTokens.bg,
      );
      return;
    }
    canvas.drawCircle(center, circleRadius, paint);
  }

  @override
  bool shouldRepaint(covariant _GitHistoryGraphPainter oldDelegate) {
    return oldDelegate.viewModel != viewModel;
  }
}

Color? _graphColor(GitHistoryGraphColorId? color) {
  return switch (color) {
    GitHistoryGraphColorId.ref => AleraTokens.success,
    GitHistoryGraphColorId.remoteRef => AleraTokens.info,
    GitHistoryGraphColorId.baseRef => AleraTokens.warning,
    GitHistoryGraphColorId.lane1 => AleraTokens.syntaxFunction,
    GitHistoryGraphColorId.lane2 => AleraTokens.syntaxKeyword,
    GitHistoryGraphColorId.lane3 => AleraTokens.syntaxLiteral,
    GitHistoryGraphColorId.lane4 => AleraTokens.syntaxOperator,
    GitHistoryGraphColorId.lane5 => AleraTokens.foregroundMuted,
    null => null,
  };
}
