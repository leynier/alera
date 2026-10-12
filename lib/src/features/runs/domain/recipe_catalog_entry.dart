/// One `recipes.catalog` entry, as New Run needs it. Settings > Recipes keeps
/// working on the raw documents.
class RecipeCatalogEntry {
  RecipeCatalogEntry.fromJson(Map<Object?, Object?> json)
    : source = Map<String, Object?>.from(json['source']! as Map),
      name = json['name'] as String?,
      description = json['description'] as String?,
      error = json['error'] as String?;

  final Map<String, Object?> source;
  final String? name;
  final String? description;
  final String? error;

  String get origin => source['origin'] as String? ?? '';

  String? get id => source['id'] as String?;

  /// Unique across origins, so it can key a dropdown.
  String get key =>
      '$origin:${source['workspaceId'] ?? ''}:${source['path'] ?? source['id']}';

  bool get usable => error == null;

  bool get isFreeform => origin == 'builtIn' && id == freeformRecipeId;

  String get originLabel => recipeOriginLabel(source);

  String get label => '${name ?? 'Invalid Recipe'} ($originLabel)';
}

/// The built-in one-stage recipe isolated runs default to.
const String freeformRecipeId = 'freeform';

String recipeOriginLabel(Map<Object?, Object?> source) =>
    switch (source['origin']) {
      'builtIn' => 'Built-in',
      'personal' => 'Personal',
      'project' => 'Project',
      _ => 'Unknown Origin',
    };

/// A recipe role New Run binds to an Agent Profile.
class RecipeRole {
  const RecipeRole({required this.id, required this.name});

  final String id;
  final String name;

  /// Reads the roles of a `recipes.recipe` record.
  static List<RecipeRole> fromRecord(Map<String, Object?> record) {
    final recipe = record['recipe'];
    final roles = recipe is Map ? recipe['roles'] : null;
    if (roles is! List) return const <RecipeRole>[];
    return <RecipeRole>[
      for (final role in roles)
        if (role is Map && role['id'] is String)
          RecipeRole(
            id: role['id']! as String,
            name: role['name'] as String? ?? role['id']! as String,
          ),
    ];
  }
}
