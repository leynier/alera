import 'package:alera/src/features/browser/domain/browser_profile.dart';

abstract interface class BrowserProfileService {
  Future<List<BrowserProfile>> list();

  Stream<List<BrowserProfile>> watchAll();

  Future<BrowserProfile> upsert({
    String? id,
    required String name,
    bool persistent = true,
    BrowserProfileSource? source,
  });

  Future<void> validateRemoval(String profileId);

  Future<bool> remove(String profileId);
}
