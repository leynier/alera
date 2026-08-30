import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:flutter/material.dart';

double mobileEmulatorStreamAspectRatio(MobileEmulatorStream? stream) {
  final width = stream?.width;
  final height = stream?.height;
  if (width == null || height == null || height == 0) {
    return 9 / 16;
  }
  return width / height;
}

double? mobileEmulatorDecodedAspectRatio({
  required int? width,
  required int? height,
  required int? rotation,
}) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  final normalizedRotation = (rotation ?? 0).abs() % 360;
  final isQuarterTurn = normalizedRotation == 90 || normalizedRotation == 270;
  return isQuarterTurn ? height / width : width / height;
}

class const MobileEmulatorLoading({super.key, final String? state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AleraTokens.space12),
          Text(
            state == 'starting'
                ? 'Starting mobile emulator'
                : 'Connecting to mobile emulator',
          ),
        ],
      ),
    );
  }
}

class const MobileEmulatorFailure({
  super.key,
  required final Object error,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final exception = error is MobileEmulatorException
        ? error as MobileEmulatorException
        : null;
    final detail = exception?.message ?? error.toString();
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          Text(
            'Mobile emulator unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space6),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AleraTokens.imageMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Text(
                  detail,
                  textAlign: .center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
                for (final step in exception?.nextSteps ?? const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(top: AleraTokens.space6),
                    child: Text(
                      step,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.foregroundMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
