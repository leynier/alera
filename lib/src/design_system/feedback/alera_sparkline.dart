import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compact trend line for a short series of samples, drawn min/max normalized
/// so a flat-but-high series and a flat-but-low one look the same.
///
/// Hand-rolled rather than pulled from a charting package: the whole widget is
/// one polyline, and a chart library would be several orders of magnitude more
/// code for the same pixels.
class const AleraSparkline({
  super.key,
  required this.samples,
  final double width = 48,
  final double height = 14,
  final Color? color,
}) extends StatelessWidget {
  /// Values oldest first. Fewer than two points draws nothing: a single sample
  /// has no trend to show.
  final List<int> samples;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          samples: samples,
          color: color ?? AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}

class const _SparklinePainter({
  required final List<int> samples,
  required final Color color,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || size.width <= 0 || size.height <= 0) {
      return;
    }
    var lowest = samples.first;
    var highest = samples.first;
    for (final sample in samples) {
      if (sample < lowest) {
        lowest = sample;
      }
      if (sample > highest) {
        highest = sample;
      }
    }
    final span = highest - lowest;
    final stepX = size.width / (samples.length - 1);
    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      // A flat series has no span to normalize against, so it rides the middle
      // instead of dividing by zero or pinning to an edge.
      final normalized = span == 0 ? 0.5 : (samples[index] - lowest) / span;
      final x = stepX * index;
      final y = size.height - (normalized * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.samples.length != samples.length) {
      return true;
    }
    for (var index = 0; index < samples.length; index++) {
      if (oldDelegate.samples[index] != samples[index]) {
        return true;
      }
    }
    return false;
  }
}
