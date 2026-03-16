# Flutter Local Databases — Research Summary

## Context

Research on Flutter local database packages (relational and non-relational) to evaluate options for the Alera project. Priority: fast iteration now, potential migration to Drift later.

---

## Options Analyzed

### Relational

| Package | Typing | Code Gen | Platforms | Maintenance |
|---------|--------|----------|-----------|-------------|
| **Drift** | Strong (Dart types, SQL) | `build_runner` (mandatory) | Android, iOS, macOS, Windows, Linux, Web | Active, well-maintained |
| **sqflite** | Weak (`Map<String, dynamic>`) | None | Android, iOS, macOS | Stable, low activity |
| **floor** | Strong (annotations + code gen) | `build_runner` (mandatory) | Android, iOS, macOS, Web | Low activity |

### Non-Relational / Key-Value

| Package | Typing | Code Gen | Platforms | Maintenance |
|---------|--------|----------|-----------|-------------|
| **Hive** | Strong (type adapters) | Optional (manual adapters or `build_runner`) | Android, iOS, macOS, Windows, Linux, Web | Maintained but infrequent |
| **Isar** | Strong (annotations + code gen) | `build_runner` (mandatory) | Android, iOS, macOS, Windows, Linux | Active |
| **ObjectBox** | Strong (annotations + code gen) | `build_runner` (mandatory) | Android, iOS, macOS, Windows, Linux | Active |
| **Sembast** | Weak (`Map<String, dynamic>`) | None | Android, iOS, macOS, Windows, Linux, Web | Active |

### Other Notable

| Package | Type | Notes |
|---------|------|-------|
| **shared_preferences** | Key-value | Simple key-value pairs, not a real database |
| **flutter_secure_storage** | Encrypted key-value | For sensitive data (tokens, credentials) |
| **realm** | Object database | Official MongoDB SDK, active maintenance |

---

## Platform Support Comparison

| Package | Android | iOS | macOS | Windows | Linux | Web |
|---------|---------|-----|-------|---------|-------|-----|
| Drift | Yes | Yes | Yes | Yes | Yes | Yes |
| sqflite | Yes | Yes | Yes | No | No | No |
| Hive | Yes | Yes | Yes | Yes | Yes | Yes |
| Isar | Yes | Yes | Yes | Yes | Yes | No |
| ObjectBox | Yes | Yes | Yes | Yes | Yes | No |
| Sembast | Yes | Yes | Yes | Yes | Yes | Yes |
| Realm | Yes | Yes | Yes | Yes | No | No |

---

## Deep Dive: ObjectBox vs Sembast

### Sembast

- **Pure Dart**, no native dependencies.
- **No code generation** — data is `Map<String, dynamic>`.
- Schema-less: add/remove fields by changing the map, no migrations needed.
- Hot reload friendly — change data shape without rebuild steps.
- Full platform support including Web (via `sembast_web`).
- Setup: `flutter pub add sembast` and start coding.

```dart
final db = await databaseFactoryIo.openDatabase('my_app.db');
final store = stringMapStoreFactory.store('sessions');

// insert
await store.add(db, {'id': 'abc', 'title': 'My Session', 'status': 'active'});

// query
final sessions = await store.find(db, finder: Finder(
  filter: Filter.equals('status', 'active'),
  sortOrders: [SortOrder('title')],
));
```

### ObjectBox

- Native C++ engine with FFI bindings (`objectbox_flutter_libs`).
- **Requires `build_runner`** for code generation.
- Annotations-based models (`@Entity`, `@Id`, etc.).
- Schema changes require re-running code generation.
- No Web support.
- Stronger typing via generated code, better raw performance.

```dart
@Entity()
class Session {
  @Id()
  int id = 0;
  String title;
  String status;
  Session({required this.title, required this.status});
}
```

---

## Comparison for Fast Iteration

| Aspect | Sembast | ObjectBox |
|--------|---------|-----------|
| Setup | One `pub add`, done | `pub add` + `build_runner` + native libs |
| Code generation | None | Mandatory on every model change |
| Schema change | Modify map, done | Change annotation + re-run `build_runner` |
| Typing | Manual (Map) | Auto-generated |
| Hot reload | Yes | No (model change = build) |
| Migration to Drift | Direct (similar concepts) | Rewrite data access layer |

---

## Recommendation

**Sembast** is the best choice for rapid iteration:

1. Zero friction — no build_runner, no code gen, no native setup.
2. Schema changes are instant — just modify the map.
3. Hot reload works naturally.
4. Full platform support including Web.
5. When ready to migrate to Drift, the mental model is similar (stores → tables, finders → queries).

ObjectBox is better suited for projects with stable schemas that need maximum performance and strong typing from day one — not the case during early iteration.
