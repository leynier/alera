import 'package:alera/src/features/ai_dictation/application/ai_dictation_model_transfers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiDictationDownloadBootstrap extends ConsumerWidget {
  const AiDictationDownloadBootstrap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      aiDictationModelTransfersProvider.select((value) => value.initialized),
    );
    return child;
  }
}
