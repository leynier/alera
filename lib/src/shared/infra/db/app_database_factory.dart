import 'dart:io';

import 'package:alera/src/shared/infra/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final dbDir = Directory(p.join(dir.path, 'db'));
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }

  final file = File(p.join(dbDir.path, 'alera.sqlite'));
  final database = AppDatabase(NativeDatabase(file));
  await database.initialize();
  return database;
}
