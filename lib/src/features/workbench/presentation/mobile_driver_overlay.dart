import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:flutter/material.dart';

/// Presence data and reclaim actions the workbench tree needs to render the
/// mobile driver overlay. Built by the feature-level shell (which consumes
/// Riverpod) so the workbench view stays presentational.
class WorkbenchMobileDriverPresence {
  const WorkbenchMobileDriverPresence({
    required this.drivers,
    required this.onReclaim,
    required this.onReclaimAll,
  });

  /// Mobile-driven sessions keyed by terminal session id.
  final Map<String, TerminalSessionDriver> drivers;
  final ValueChanged<String> onReclaim;
  final VoidCallback onReclaimAll;
}

/// Banner shown over a terminal pane while a mobile device drives its
/// viewport (the mobile presence lock). The terminal output stays visible;
/// the banner offers taking the seat back and collapses to a small chip so
/// live output can be watched. Presentational: state and actions come from
/// the feature-level gate.
class MobileDriverOverlay extends StatefulWidget {
  const MobileDriverOverlay({
    super.key,
    required this.deviceName,
    required this.drivenCount,
    required this.onTakeBack,
    required this.onTakeBackAll,
  });

  final String deviceName;

  /// How many terminals are currently mobile-driven; enables Take Back All.
  final int drivenCount;
  final VoidCallback onTakeBack;
  final VoidCallback onTakeBackAll;

  @override
  State<MobileDriverOverlay> createState() => _MobileDriverOverlayState();
}

class _MobileDriverOverlayState extends State<MobileDriverOverlay> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space12),
        child: _collapsed ? _buildChip() : _buildBanner(),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.smartphone,
                size: AleraTokens.space16,
                color: AleraTokens.info,
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(
                '${widget.deviceName} is driving this terminal',
                style: const TextStyle(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              IconButton(
                tooltip: 'Collapse',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _collapsed = true),
                icon: const Icon(
                  Icons.close_fullscreen,
                  size: AleraTokens.space16,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space4),
          const Text(
            'Desktop keyboard is paused',
            style: TextStyle(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(
                onPressed: widget.onTakeBack,
                child: const Text('Take Back This Terminal'),
              ),
              if (widget.drivenCount > 1) ...<Widget>[
                const SizedBox(width: AleraTokens.space8),
                OutlinedButton(
                  onPressed: widget.onTakeBackAll,
                  child: const Text('Take Back All Terminals'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.smartphone,
            size: AleraTokens.space12,
            color: AleraTokens.info,
          ),
          const SizedBox(width: AleraTokens.space6),
          const Text(
            'Phone driving',
            style: TextStyle(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(width: AleraTokens.space8),
          TextButton(
            onPressed: widget.onTakeBack,
            child: const Text('Take Back'),
          ),
          IconButton(
            tooltip: 'Expand',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _collapsed = false),
            icon: const Icon(
              Icons.open_in_full,
              size: AleraTokens.space12,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
