import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_providers.g.dart';

@Riverpod(keepAlive: true)
Future<AleraDatabase> aleraDatabase(Ref ref) async {
  final db = await openAleraDb();
  ref.onDispose(() async {
    await db.close();
  });
  return db;
}
