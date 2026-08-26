import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_credential_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_openai_dictation_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:logging/logging.dart';

part 'mobile_ai_dictation_provider_credentials.g.dart';

final _credentialLog = Logger('MobileAiDictationCredentials');

@Riverpod(keepAlive: true)
MobileAiDictationCredentialStore mobileAiDictationCredentialStore(Ref ref) {
  return MobileAiDictationCredentialStore();
}

@Riverpod(keepAlive: true)
MobileOpenAiDictationProvider mobileOpenAiDictationProvider(Ref ref) {
  return MobileOpenAiDictationProvider(
    ref.read(mobileAiDictationCredentialStoreProvider),
  );
}

@riverpod
Future<MobileAiDictationCredentialStatus> mobileAiDictationCredentialStatus(
  Ref ref,
  String baseUrl,
) async {
  try {
    return await ref
        .read(mobileAiDictationCredentialStoreProvider)
        .status(baseUrl);
  } on Object catch (error, stackTrace) {
    _credentialLog.warning(
      'mobile dictation token status failed',
      error,
      stackTrace,
    );
    rethrow;
  }
}
