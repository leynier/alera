# Plan: sistema de proyectos con chats y worktrees

## Context

Hoy una "sesión" en Alera es 1:1 con un workspace (path de un repo git) y vive solo en memoria — el usuario debe re-elegir la carpeta cada vez que abre la app y no hay forma de tener varios chats sobre el mismo repo. El feature pedido introduce un primer ciudadano "Project" (= un repo registrado) que agrupa una lista de chats persistidos. Cada chat puede correr sobre el repo principal o sobre un worktree dedicado, lo que habilita trabajar en paralelo en ramas distintas sin pisarse. El objetivo es conservar la UX actual del session_workspace pero anteponer una capa de proyectos y chats listables, con persistencia local vía Sembast y operaciones reales de `git worktree`.

Decisiones ya cerradas con el usuario:

- **Worktrees** viven en `~/.alera/worktrees/<repo-slug>/<worktree-name>` (path global configurable).
- **1 chat = 1 worktree** (aislamiento total, cleanup simple).
- **Branch del worktree** se crea con prefijo `alera/<nombre>` desde el HEAD del repo principal al momento de crear.
- **Cleanup**: al borrar un chat con worktree, preguntar al usuario si conservar o eliminar worktree + branch.
- **Persistencia (Sembast)**: proyectos + chats + historial completo (texto + rol, tool calls como display-only, token/cost por turno, thread/turn IDs como referencia).
- **Navegación**: sidebar permanente con proyectos colapsables que listan sus chats.
- **Alta de proyectos**: botón explícito "Add project" → folder picker → valida git repo → registra.

## Architecture overview

```
lib/src/features/
  projects/            (extender)
    domain/
      project.dart                     [NEW]  modelo Project
      worktree.dart                    [NEW]  modelo Worktree
    application/
      project_service.dart             [edit] añadir CRUD + listado
      worktree_service.dart            [NEW]  git worktree add/remove/list
      project_repository.dart          [NEW]  interface
    infra/
      sembast_project_repository.dart  [NEW]  Sembast DAO proyectos
      sembast_chat_repository.dart     [NEW]  Sembast DAO chats + mensajes
    presentation/
      add_project_dialog.dart          [NEW]
      new_chat_dialog.dart             [NEW]  elegir main repo vs worktree+nombre
      delete_chat_dialog.dart          [NEW]  preguntar si limpiar worktree
  session/             (refactor)
    application/
      session_controller.dart          [edit] hidratar desde DB, asociar projectId
      session_service.dart             [edit] persistir cada turno
  shell/               (refactor)
    presentation/
      alera_shell_page.dart            [edit] shell con sidebar
      project_sidebar.dart             [NEW]  sidebar colapsable proyectos→chats
shared/
  infra/storage/
    sembast_database.dart              [NEW]  factory + migraciones
  models/contracts.dart                [edit] AleraSession.projectId, worktreeId
```

## Data model

### Sembast stores

| Store | Key | Document shape |
| --- | --- | --- |
| `projects` | `projectId` (uuid) | `{id, name, repoPath, createdAt, updatedAt}` |
| `worktrees` | `worktreeId` (uuid) | `{id, projectId, name, branch, path, createdAt, status}` |
| `chats` | `chatId` (uuid, == AleraSession.id) | `{id, projectId, worktreeId?, title, model, threadId?, lastTurnId?, createdAt, updatedAt}` |
| `chat_messages` | compound `${chatId}/${seq}` | `{chatId, seq, role, text, toolCallsJson?, tokensIn?, tokensOut?, costUsd?, turnId?, createdAt}` |
| `meta` | `key` | versión de schema, último proyecto activo, último chat por proyecto |

Sembast es schemaless — la "migración" se reduce a leer `meta.schemaVersion` y aplicar transformaciones idempotentes si el shape cambia (no aplica para v1).

### Dart models nuevos (`projects/domain/`)

- `Project { id, name, repoPath, createdAt, updatedAt }`
- `Worktree { id, projectId, name, branch, path, createdAt, status (active|removed) }`
- Extender `AleraSession` (en `shared/models/contracts.dart`) con `projectId` (required) y `worktreeId?` (null = corre sobre el repo principal).

## Persistencia (Sembast)

### Setup

- Añadir `sembast: ^3.x` y `sembast_web` a `pubspec.yaml` (web a futuro), más `path_provider` si no estaba ya.
- Nuevo `lib/src/shared/infra/storage/sembast_database.dart`:
  - `Future<Database> openAleraDb()` resuelve `<appSupportDir>/alera.db` y guarda `meta.schemaVersion`.
  - Provider Riverpod `aleraDatabaseProvider` en `lib/src/app/providers.dart`.
- En tests usar `databaseFactoryMemory` para no tocar disco.

### Repositorios

- `ProjectRepository` (interface + impl Sembast):
  - `Stream<List<Project>> watchAll()` → reactivo para sidebar.
  - `Future<Project> add(repoPath, name)`, `update`, `remove(id)`.
- `ChatRepository`:
  - `Stream<List<ChatSummary>> watchByProject(projectId)`.
  - `Future<List<ChatMessage>> loadMessages(chatId)`.
  - `Future<void> appendMessage(chatId, ChatMessage)` — write-through cada turno.
  - `Future<void> remove(chatId, {bool cascadeMessages = true})`.
- Las cosas que ya viven en `PreferencesStore` (model, reasoning, etc.) se quedan donde están — Sembast es solo para datos del dominio nuevos.

## Worktree service

Nuevo `lib/src/features/projects/application/worktree_service.dart`. Usa el `ProcessRunner` ya existente (`lib/src/shared/infra/process/process_runner.dart`):

```dart
class WorktreeService {
  Future<Worktree> create({
    required Project project,
    required String name,        // input crudo del usuario
  }) async {
    final slug = _slug(name);
    final branch = 'alera/$slug';
    final path = await _resolveWorktreePath(project, slug); // ~/.alera/worktrees/<repoSlug>/<slug>
    await _runner.run('git', ['worktree', 'add', '-b', branch, path], cwd: project.repoPath);
    return Worktree(id: uuid(), projectId: project.id, name: slug, branch: branch, path: path, ...);
  }

  Future<void> remove(Worktree wt, {required bool deleteBranch}) async {
    await _runner.run('git', ['worktree', 'remove', '--force', wt.path], cwd: ...);
    if (deleteBranch) {
      await _runner.run('git', ['branch', '-D', wt.branch], cwd: project.repoPath);
    }
  }

  Future<List<Worktree>> reconcile(Project project) { /* git worktree list --porcelain → cruzar con DB */ }
}
```

- `_resolveWorktreePath` lee la base configurable (`AleraConfig.worktreesRoot`, default `~/.alera/worktrees`) y deriva `<repoSlug>` desde `project.repoPath` (`basename + 8 hex chars de hash` para evitar colisiones entre repos con mismo nombre).
- `_slug` valida `[a-z0-9-]+`, recorta espacios y reemplaza separadores.
- Errores de `git` se envuelven en `WorktreeException` con stderr; la UI los muestra en el diálogo.
- En arranque de la app, `reconcile` corre por cada proyecto para marcar como `removed` worktrees borrados manualmente desde fuera.

## Session/chat refactor

- `SessionCreateRequest` añade `projectId` y `worktreeId?`. El `projectPath` que ya existe se sigue derivando: si hay `worktreeId`, es el path del worktree; si no, es `project.repoPath`.
- `SessionController.bootstrap()` hidrata el estado desde Sembast: lista de proyectos, último proyecto activo, último chat de ese proyecto.
- `SessionService.createSession(request)`:
  1. Si `request.worktreeName != null` → `WorktreeService.create(...)` antes de crear el chat.
  2. Inserta `Project`/`Worktree`/`Chat` en Sembast.
  3. Crea el thread en codex apuntando al path correcto.
- Cada turno persiste su(s) mensaje(s) vía `ChatRepository.appendMessage`. Los tool calls se serializan a JSON y se guardan como display-only (`persistence-in-reference-orchestrators.md` recomendación).
- Al abrir un chat existente: cargar mensajes desde Sembast, intentar `thread/resume` con el `threadId` guardado; si falla, mostrar UI offline con banner "history is read-only — start a new turn to rehydrate".

## UI changes

### Shell con sidebar (`alera_shell_page.dart` + `project_sidebar.dart`)

- Layout `Row`: `ProjectSidebar` (≈ 260dp, `surfaceVariant`, `radiusLg` en bordes interiores) + el `SessionWorkspaceView` actual.
- Sidebar:
  - Header con botón `FilledButton.icon(Icons.add)` "Add project".
  - `ListView` de `ExpansionTile` por proyecto (estado guardado en `projects.<id>.expanded` en Sembast `meta`).
  - Dentro de cada proyecto: lista de chats (título, marcador `worktree:<name>` cuando aplica usando `radiusSm` chip), botón "+ New chat".
  - Long-press / hover → menú con "Rename project", "Remove project", "Open in Finder".
  - Estado vacío: ilustración + CTA "Add your first project".
- Top bar pierde el selector de workspace (queda como breadcrumb del chat activo: `<project> / <chat title>`).

### Add project (`add_project_dialog.dart`)

- Folder picker (`file_selector` ya en uso en el shell actual).
- Llama a `ProjectService.validateGitRepository` (ya existe) y muestra error tokenizado si falla.
- Pide nombre opcional (default = `basename(repoPath)`).
- Confirmar → `ProjectRepository.add` → seleccionar el proyecto en sidebar.

### New chat (`new_chat_dialog.dart`)

- Radio group con 2 opciones (`radiusMd`, sin literales de color):
  1. **Use main repo** — descripción: corre sobre `project.repoPath`, branch actual.
  2. **New worktree** — input de nombre debajo, validación live (`[a-z0-9-]+`, no duplicados), preview del path resultante (`~/.alera/worktrees/<repo>/<name>`) y del branch (`alera/<name>`).
- Botones: `TextButton` "Cancel", `FilledButton` "Create chat".
- Loader mientras corre `git worktree add`. Error → toast con stderr y permanece abierto.

### Delete chat (`delete_chat_dialog.dart`)

- Solo aparece si el chat tiene `worktreeId`.
- Texto: "This chat is linked to worktree `<name>` (branch `alera/<name>`). What should we do with it?"
- 3 acciones:
  - `TextButton` "Cancel".
  - `OutlinedButton` "Keep worktree" — borra solo el chat de la DB.
  - `FilledButton` (estilo destructivo, `error`/`onError`) "Delete worktree + branch" — borra chat, corre `git worktree remove --force`, `git branch -D`, marca worktree `removed`.

### Tokens / design system

Todos los nuevos widgets MUST usar `AleraTokens` (`space*`, `radius*`, color tokens) y `ThemeData`. Botones siguen la tabla A de AGENTS.md (Primary/Secondary/Destructive/Inline). Sin literales visuales nuevos.

## Critical files to modify

- `lib/src/app/providers.dart` — registrar `aleraDatabaseProvider`, `projectRepositoryProvider`, `chatRepositoryProvider`, `worktreeServiceProvider`.
- `lib/src/shared/models/contracts.dart` — añadir `projectId`/`worktreeId` a `AleraSession`/`SessionCreateRequest`.
- `lib/src/features/session/application/session_controller.dart` — bootstrap desde DB, asociar projectId, persistir mensajes.
- `lib/src/features/session/application/session_service.dart` — coordinar creación con `WorktreeService`.
- `lib/src/features/projects/application/project_service.dart` — extender con CRUD (reutilizar `validateGitRepository`, `listGitBranches` existentes).
- `lib/src/features/shell/presentation/alera_shell_page.dart` — quitar `_SelectWorkspaceDialog` (lines 258-493), insertar layout con sidebar, mover folder picker a `add_project_dialog.dart`.
- `pubspec.yaml` — añadir `sembast` (+ `sembast_web` si se quiere preparar web), `path_provider` si falta, `path` si falta.

## Reuso de código existente

- `ProcessRunner` / `IoProcessRunner` (`lib/src/shared/infra/process/process_runner.dart`) → ejecutar `git worktree`.
- `ProjectService.validateGitRepository` y `ProjectService.listGitBranches` → reutilizar tal cual en flow de alta.
- `PreferencesStore` → seguir usando para settings (no migrar a Sembast).
- `SessionController` / `SessionState` → conservar API pública y solo extender con `projectId` y métodos de carga desde DB.
- File picker actual en `_SelectWorkspaceDialog` → moverlo, no reescribirlo.

## Verification

1. **Unit tests** (Sembast en memoria):
   - `ProjectRepository`: add → watchAll emite → remove → emite.
   - `ChatRepository`: appendMessage en orden mantiene `seq`; loadMessages ordena correctamente; remove cascade borra mensajes.
   - `WorktreeService` con un `FakeProcessRunner` que captura argv: verificar `git worktree add -b alera/<slug>` y `remove --force`/`branch -D` con los flags correctos.
2. **Integration test** (`flutter test integration_test/`):
   - Crear proyecto sobre un repo git temporal (`git init` en `setUp`).
   - Crear chat con worktree `feature-x` → assert que el dir existe, branch existe, registro en DB.
   - Crear segundo chat sobre main repo → assert no toca worktrees.
   - Borrar chat con worktree con opción "delete" → assert dir y branch se fueron y registro marcado removed.
3. **Manual smoke** (`flutter run -d macos`):
   - Add project apuntando a `/Volumes/ExternalStorage/Projects/alera` mismo.
   - Crear chat sobre worktree `test-1`, verificar `~/.alera/worktrees/alera-XXXXXXXX/test-1` y `git -C <repo> branch | grep alera/test-1`.
   - Cerrar y reabrir la app: proyecto y chats persisten, último chat selecciona automáticamente.
   - Borrar chat con "delete worktree + branch" → directorio y rama desaparecen.
4. **Lint / análisis**: `flutter analyze` sin warnings nuevos; verificar conformancia con AGENTS.md (no literales de color/spacing/radius).
