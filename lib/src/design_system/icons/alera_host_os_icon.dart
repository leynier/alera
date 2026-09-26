import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_codicons.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Operating system of a workspace host, as reported by SSH bootstrap.
enum HostOs {
  macos,
  windows,
  linux,
  unknown;

  /// Accepts the spellings the sidecar and bootstrap probes emit
  /// (`macos`/`darwin`, `windows`/`win32`, `linux`). Anything else is
  /// [unknown] so callers fall back to the generic host glyph.
  static HostOs parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'macos' || 'darwin' || 'mac' => HostOs.macos,
      'windows' || 'win32' || 'win' => HostOs.windows,
      'linux' => HostOs.linux,
      _ => HostOs.unknown,
    };
  }

  String get label => switch (this) {
    HostOs.macos => 'macOS',
    HostOs.windows => 'Windows',
    HostOs.linux => 'Linux',
    HostOs.unknown => 'Unknown OS',
  };
}

/// Glyph for a host operating system: Apple for macOS, the Windows tile logo,
/// Tux for Linux, and the generic host icon when the platform is unknown.
///
/// Lucide ships an Apple mark and Codicons ship Tux, but neither has a
/// Windows logo, so that one is painted as the four-tile mark at the same
/// optical size.
class const AleraHostOsIcon({
  super.key,
  required final HostOs os,
  this.size = AleraTokens.iconSm,
  this.color = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (os) {
      HostOs.macos => Icon(LucideIcons.apple, size: size, color: color),
      HostOs.linux => Icon(
        AleraCodicons.terminalLinux,
        size: size,
        color: color,
      ),
      HostOs.windows => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _WindowsLogoPainter(color: color)),
      ),
      HostOs.unknown => Icon(AleraIcons.host, size: size, color: color),
    };
  }
}

class _WindowsLogoPainter extends CustomPainter {
  const _WindowsLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Inset so the mark matches the visual weight of the neighbouring
    // stroke icons instead of filling the whole box.
    final inset = size.shortestSide * 0.12;
    final side = size.shortestSide - inset * 2;
    final gap = side * 0.1;
    final tile = (side - gap) / 2;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    for (final dx in <double>[0, tile + gap]) {
      for (final dy in <double>[0, tile + gap]) {
        canvas.drawRect(Rect.fromLTWH(left + dx, top + dy, tile, tile), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WindowsLogoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
