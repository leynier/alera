import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/runs/presentation/recipe_catalog_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

/// Settings > Recipes: the run template catalog.
SettingsSectionData recipeSettingsSection() => SettingsSectionData(
  id: 'recipes',
  title: 'Recipes',
  description:
      'Run templates: stages, roles, gates and portable role contracts.',
  icon: AleraIcons.workspaceChildren,
  navGroup: SettingsNavGroup.resources,
  entries: const [
    SettingsSearchEntry(
      title: 'Recipes',
      keywords: [
        'templates',
        'runs',
        'catalog',
        'personal',
        'project',
        'built-in',
        'yaml',
        'contracts',
        'export',
      ],
    ),
  ],
  builder: (_) => const RecipeCatalogPane(),
);
