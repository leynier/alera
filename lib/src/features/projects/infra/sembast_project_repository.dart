import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastProjectRepository implements ProjectRepository {
  SembastProjectRepository(this._db);

  final Database _db;

  @override
  Future<List<Project>> listAll() async {
    final records = await AleraStores.projects.find(
      _db,
      finder: Finder(sortOrders: <SortOrder>[SortOrder('updatedAt', false)]),
    );
    return records
        .map((r) => Project.fromJson(r.value))
        .toList(growable: false);
  }

  @override
  Stream<List<Project>> watchAll() {
    return AleraStores.projects
        .query(
          finder: Finder(
            sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((r) => Project.fromJson(r.value))
              .toList(growable: false),
        );
  }

  @override
  Future<Project> add(Project project) async {
    await AleraStores.projects.record(project.id).put(_db, project.toJson());
    return project;
  }

  @override
  Future<Project> update(Project project) async {
    await AleraStores.projects.record(project.id).put(_db, project.toJson());
    return project;
  }

  @override
  Future<void> remove(String projectId) async {
    await _db.transaction((txn) async {
      await AleraStores.projects.record(projectId).delete(txn);
      // Cascade-delete worktrees and chats belonging to the project. Chat
      // messages are removed via the chat repository when the caller deletes
      // the chats — we still wipe the chat records here so orphaned data does
      // not linger if the chat repository wasn't involved.
      final worktreeRecords = await AleraStores.worktrees.find(
        txn,
        finder: Finder(filter: Filter.equals('projectId', projectId)),
      );
      for (final r in worktreeRecords) {
        await AleraStores.worktrees.record(r.key).delete(txn);
      }
      final chatRecords = await AleraStores.chats.find(
        txn,
        finder: Finder(filter: Filter.equals('projectId', projectId)),
      );
      for (final r in chatRecords) {
        await AleraStores.chats.record(r.key).delete(txn);
        final messageRecords = await AleraStores.chatMessages.find(
          txn,
          finder: Finder(filter: Filter.equals('chatId', r.key)),
        );
        for (final m in messageRecords) {
          await AleraStores.chatMessages.record(m.key).delete(txn);
        }
        final cellRecords = await AleraStores.chatCells.find(
          txn,
          finder: Finder(filter: Filter.equals('chatId', r.key)),
        );
        for (final c in cellRecords) {
          await AleraStores.chatCells.record(c.key).delete(txn);
        }
      }
    });
  }

  @override
  Future<List<Worktree>> listWorktrees(String projectId) async {
    final records = await AleraStores.worktrees.find(
      _db,
      finder: Finder(
        filter: Filter.equals('projectId', projectId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    return records
        .map((r) => Worktree.fromJson(r.value))
        .toList(growable: false);
  }

  @override
  Stream<List<Worktree>> watchWorktrees(String projectId) {
    return AleraStores.worktrees
        .query(
          finder: Finder(
            filter: Filter.equals('projectId', projectId),
            sortOrders: <SortOrder>[SortOrder('createdAt', true)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((r) => Worktree.fromJson(r.value))
              .toList(growable: false),
        );
  }

  @override
  Future<Worktree> addWorktree(Worktree worktree) async {
    await AleraStores.worktrees.record(worktree.id).put(_db, worktree.toJson());
    return worktree;
  }

  @override
  Future<Worktree> updateWorktree(Worktree worktree) async {
    await AleraStores.worktrees.record(worktree.id).put(_db, worktree.toJson());
    return worktree;
  }

  @override
  Future<Worktree?> findWorktreeById(String worktreeId) async {
    final record = await AleraStores.worktrees.record(worktreeId).get(_db);
    if (record == null) {
      return null;
    }
    return Worktree.fromJson(record);
  }
}
