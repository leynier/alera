import 'package:dart_mappable/dart_mappable.dart';

part 'home_composer_prefs.mapper.dart';

/// Last choices made in the Home composer, so the next prompt starts where the
/// previous one left off. Ids that no longer resolve fall back to defaults.
@MappableClass()
class const HomeComposerPrefs({
  this.projectId,
  this.profileId,
  this.projects = const <String, HomeComposerProjectPrefs>{},
}) with HomeComposerPrefsMappable {
  final String? projectId;
  final String? profileId;

  /// Host, parent, and location are remembered per project because each
  /// project has its own hosts and branches.
  final Map<String, HomeComposerProjectPrefs> projects;

  static const HomeComposerPrefs empty = HomeComposerPrefs();
}

@MappableClass()
class const HomeComposerProjectPrefs({
  this.hostId,
  this.parentWorkspaceId,
  this.useProjectCheckout = true,
  this.sourceBranch,
}) with HomeComposerProjectPrefsMappable {
  final String? hostId;
  final String? parentWorkspaceId;
  final bool useProjectCheckout;
  final String? sourceBranch;
}
