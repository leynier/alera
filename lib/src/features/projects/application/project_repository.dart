import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';

abstract interface class ProjectRepository {
  Future<List<Project>> listAll();

  Stream<List<Project>> watchAll();

  Future<Project> add(Project project);

  Future<Project> update(Project project);

  Future<void> remove(String projectId);

  Future<List<Worktree>> listWorktrees(String projectId);

  Stream<List<Worktree>> watchWorktrees(String projectId);

  Future<Worktree> addWorktree(Worktree worktree);

  Future<Worktree> updateWorktree(Worktree worktree);

  Future<Worktree?> findWorktreeById(String worktreeId);
}
