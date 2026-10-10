# Plan de implementación: paridad máxima del MCP de Alera

Fecha: 2026-10-10. Base de código: `c8b3d3984` (v0.104.1). Documento de partida: [mcp-capability-gap-audit.md](mcp-capability-gap-audit.md). Es **solo un plan**: no se implementó código.

Estructura: spec → diseño → tareas por fases y PRs → pruebas → supuestos y decisiones residuales.

**Revisión 2 (2026-10-10).** Incorpora las cuatro decisiones finales F1-F4, tomadas tras la revisión crítica, y las correcciones C1-C8 de esa revisión. El resumen de cambios está en la sección 0.1.

## 0. Decisiones del usuario (vinculantes)

| # | Decisión | Cómo la aplica este plan |
|---|---|---|
| U1 | Añadir un nivel **Admin** separado de Off, Read y Full. Los grants actuales no reciben admin automáticamente | Nivel `admin` en el runtime (MCP Control) y scope OAuth `mcp:admin`, con doble barrera como hoy (sección 3) |
| U2 | Sin preview, confirmToken ni aprobaciones externas para lo destructivo; flujo de la UI y confirmaciones normales del cliente dentro de los scopes | Las herramientas destructivas llevan `destructiveHint: true` y ejecutan el flujo de la UI en una sola llamada |
| U3 | Borrar workspaces exactamente como la UI, con la opción de conservar o eliminar la rama y sin preguntas extra; los cambios locales siguen la semántica de la UI | `remove_workspace` replica el lanzador desktop (sección 6.3) |
| U4 | Excluir el plano de control de seguridad, el consentimiento OAuth, el emparejamiento de dispositivos y el escalado de privilegios | Lista de exclusiones en 2.3, impuesta por un test |
| U5 | CRUD de automations y agent profiles con FULL; las automations pueden nacer activas; las decisiones humanas de sí/no solo desde la UI de Alera | Gates, run policy y decisiones de workflows quedan excluidos, también con test |
| U6 | No exponer Explorer, Search, la gestión general de Source Control ni la lectura de archivos o diffs. Sí el grupo PR: Restack, Ship Changes, Watch and Fix, Merge y las acciones de PR necesarias | Fase 7 |
| U7 | Buzón **compartido** entre clientes MCP, con atribución del cliente de origen y destino, filtros e identificación; historial compartido | Fase 5 (sección 6.4) |
| U8 | Todos los mecanismos de notificación viables: polling robusto como fallback, MCP Events con go/no-go tras una prueba real, webhooks genéricos y suscripciones locales. Los eventos llevan IDs y el detalle se recupera con tools | Fase 8 (sección 6.5) |
| U9 | Servicio backend asíncrono y reutilizable de New Workspace from Prompt, con inferencia de identidad, sección y proyecto, fallback a "Others" y ambigüedad explícita; máxima equivalencia con la UI y worktree cuando corresponda | Fase 1 (sección 6.1) |
| U10 | Política de `mcp serve` local sin acordar | Default elegido en la sección 11 (no bloquea) |
| F1 | Full puede borrar workspaces y proyectos, hacer merge de PR y de stacks, usar fixAndMerge y purgar automations. Admin queda para la administración avanzada del runtime y las operaciones internas sensibles (opción B). Sin confirmaciones fuera del flujo de la UI | Sección 3.2; sustituye la asignación anterior de Admin |
| F2 | Agent Profiles: Full solo lista, consulta y **usa** perfiles existentes. Crear, editar, borrar, reordenar o cambiar cualquier configuración (incluidas reduced protections y el perfil por defecto) requiere Admin | Sustituye la parte de perfiles de U5 |
| F3 | Pull requests en GitHub, GitLab y Azure DevOps dentro del alcance completo, reutilizando la implementación del desktop cuando proceda | Fase 7 rehecha (sección 6.4) |
| F4 | Prueba real de extremo a extremo de OpenAI MCP Events con la integración de Alera ya conectada en ChatGPT. Se verifican los requisitos de protocolo, plugin y permisos sin suponer que la conexión actual soporta eventos. Se mantiene el polling como fallback | Fase 8: las tareas 8.0 y 8f son obligatorias |

### 0.1 Cambios de la revisión 2

- **Admin reducido (F1):** pasan a Full `remove_workspace`, `remove_project`, `merge_pull_request`, `merge_pull_request_stack`, el seguimiento `fixAndMerge` y `purge_automations`. Ship y watch vuelven a ser una sola herramienta cada uno.
- **Perfiles (F2):** `create_agent_profile`, `update_agent_profile`, `remove_agent_profile`, `reorder_agent_profiles` y `set_default_agent_profile` pasan a Admin. `launch_agent` sigue en Full. Desaparece la regla especial de `confirmReducedProtections`, porque toda mutación de perfiles ya es Admin.
- **PR multi-forja (F3):** la antigua fase opcional 7e entra en el alcance. El runtime tendrá una abstracción `ForgeProvider` con GitHub, GitLab y Azure DevOps, Watch and Fix y Ship para las tres forjas, y fixtures compartidas con las pruebas del desktop.
- **MCP Events (F4):** nueva tarea 8.0 de verificación de requisitos con la conexión existente, que se adelanta al inicio del proyecto. La prueba E2E 8f es obligatoria.
- **Correcciones C1-C8:**
  - los eventos solo se reenvían a la nube si hay suscripciones activas;
  - el diario de eventos se escribe antes del gate de push;
  - sin AI Assist, se devuelve el mismo error que la UI (se elimina la identidad determinista);
  - el prompt se guarda en claro hasta completar la operación y después solo su hash;
  - los recibos de idempotencia viven en el host;
  - error de step-up para herramientas Admin;
  - sin doble tab Setup durante la migración;
  - las previews de borrado son opcionales.
- **Estimación:** pasa de unos 76 a unos 90 días-persona (sección 8).

## 1. Spec

### 1.1 Objetivo

Que cualquier capacidad de la GUI (desktop y mobile) o del CLI de Alera que cambie o lea estado del runtime esté disponible por MCP, en local (stdio) y en remoto (edge). Las únicas excepciones son las de U4, U5 y U6 y el estado puramente de presentación. Toda herramienta debe:

- tener la misma semántica que la UI
- ser idempotente cuando muta
- ser atribuible al cliente que la usa
- cumplir el límite de tiempo de los clientes hospedados

### 1.2 Criterios de éxito globales

1. La matriz de la sección 2 queda cubierta al 100%: cada fila "Incluida" tiene herramienta, comando CLI, test de catálogo y al menos un test de comportamiento.
2. Ninguna herramienta excede 58 s. Las operaciones largas devuelven un `operationId` y se siguen con esperas acotadas.
3. Toda mutación acepta `clientRequestId`; reintentar con la misma clave no duplica efectos.
4. Admin no se concede a grants existentes; un test de contrato en la nube lo cubre.
5. Un test falla si alguna herramienta invoca un grupo o verbo excluido.
6. New Workspace from Prompt produce por MCP el mismo resultado que la UI (nombre, rama, sección o "Others", setup, agente), y la UI desktop y mobile pasan a usar el mismo servicio.
7. Un cliente MCP se entera de las respuestas del inbox y de los cambios de estado sin sondear cada pregunta: `wait_for_events` o `wait_for_inbox` en todos los clientes, suscripción en stdio, webhooks, y MCP Events en ChatGPT si supera el go/no-go.

### 1.3 No objetivos

- Explorer, búsqueda o reemplazo, quick open, editor, lectura de archivos o diffs, Reading Diff y Source Control general (stage, commit, push, ramas, stash, historial) (U6).
- Plano de control de seguridad (U4) y decisiones humanas (U5).
- Estado de presentación: layout, splits, paneles, preferencias de vista, tema, atajos, zoom.
- Cambiar los protocolos estrictos terminal-host o mobile. Todo es aditivo, con capabilities.

## 2. Inventario de cobertura (GUI y CLI → MCP)

Leyenda:

- **Nivel**: R = Read, F = Full (ejecución), A = Admin.
- **CLI**: `existe` = comando actual; `nuevo` = comando a crear; `ampliar` = flags nuevos.
- **Fase**: ver la sección 8.
- Las herramientas existentes conservan su nombre y su contrato, con ampliaciones solo aditivas.

### 2.1 Herramientas incluidas

#### Runtime, host y diagnóstico

| Capacidad (origen) | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Estado del runtime (D) | `runtime status` (existe) | `runtime_status` | R | — |
| Versiones y contratos (CLI) | `version` (existe) | `get_version` | R | 0 |
| Ajustes del runtime no sensibles: perfil por defecto, carpeta de workspaces, confirmaciones de borrado, AI Assist sin credenciales, retención de automations (D, M) | `runtime settings show/set` (nuevo, con allowlist de claves) | `get_runtime_settings` / `update_runtime_settings` | R / A | 4 |
| Integraciones de agentes (hooks) (D, CLI) | `runtime agents status/enable/disable` (existe) | `get_agent_integrations` / `set_agent_integrations` | R / A | 4 |
| Snapshot de recursos (D) | `runtime resources` (nuevo → `resources.snapshot`) | `get_resource_snapshot` | R | 4 |
| Cuotas de agentes (D, M) | `agent-quota show/refresh-claude/consume-codex-reset` (nuevo) | `get_agent_quotas` / `refresh_claude_quota` / `consume_codex_reset_credit` | R / F / A | 4 |
| Voz: hablar al humano y estado (D, M, CLI) | `voice speak/status` (existe) | `voice_speak` / `voice_status` | F / R | 4 |
| SSH targets: lista y estado (D, CLI) | `ssh-target list/status` (existe) | `list_ssh_targets` / `ssh_target_status` | R | 3 |
| Leer un issue (D, CLI) | `issue show` (existe) | `fetch_issue` | R | 2 |

#### Proyectos

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Listar | `project list` (existe) | `list_projects` | R | — |
| Registrar carpeta local (D, M) | `project add` (existe) | `register_project` | F | 3 |
| Clonar desde URL, con progreso y cancelación (D, M) | `project clone start/list/show/cancel` (nuevo → `project.clone.*`) | `clone_project` / `get_project_clone` / `list_project_clones` / `cancel_project_clone` | F / R / R / F | 3 |
| Registrar proyecto o checkout remoto (D, CLI) | `project add-remote`, `register-checkout` (existe) | `register_remote_project` / `register_project_checkout` | F | 3 |
| Renombrar (D, M) | `project rename` (nuevo → `project.rename`) | `rename_project` | F | 3 |
| Vista previa de borrado (M) | `project remove-preview` (nuevo → `project.remove.preview` + `project.removalDependencies`) | `preview_project_removal` | R | 3 |
| Borrar proyecto como la UI: pausa automations dependientes y nunca borra archivos (D, M) | `project remove --pause-automations-and-cancel-runs` (existe) | `remove_project` | F | 3 |
| Hosts del proyecto (D, CLI) | `project hosts list/add/remove` (existe) | `list_project_hosts` / `add_project_host` / `remove_project_host` | R / F / F | 3 |
| Catálogo de ramas (D, M) | `project branches` (nuevo → `project.branches.list`) | `list_project_branches` | R | 3 |
| Configuración del proyecto: New Workspace, copias, setup, proveedor de PR (D, M) | `project config show/set/remove` (nuevo → `projectConfig.*`) | `get_project_config` / `update_project_config` / `reset_project_config` | R / F / F | 3 |

#### Workspaces

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Listar, con filtros nuevos: sección, tag, archivado, padre, host | `workspace list` (ampliar) | `list_workspaces` (ampliar) | R | 2 |
| Ver detalle: sección, tags, issue, watch, PR enlazado, padre e hijos | `workspace show` (nuevo) | `show_workspace` | R | 2 |
| Crear manual: carpeta del proyecto o worktree, rama nueva o existente, padre, sección por id o nombre, issue, host, ruta | `workspace add` (existe) | `create_workspace` (ampliar: `parentWorkspaceId`, `sectionId`, `reuseExistingBranch`, `path`, `workspaceRoot`, `clientRequestId`) | F | 2 |
| New Workspace from Prompt (servicio, ver 6.1) | `workspace prompt-start run/show/list/wait/cancel/retry-launch` (nuevo) | `start_workspace_from_prompt` / `get_workspace_start` / `wait_for_workspace_start` / `list_workspace_starts` / `cancel_workspace_start` / `retry_workspace_start_launch` | F / R / R / R / F / F | 1 |
| Crear y lanzar con identidad explícita (compatibilidad) | `workspace start` (corregir defaults) | `start_agent_workspace` (se mantiene; documentado como "manual") | F | 1 |
| Renombrar | `workspace rename` (existe) | `rename_workspace` | F | 2 |
| Fijar o desfijar, también el árbol (D, M) | `workspace pin/unpin` (ampliar `--tree`) | `set_workspace_pinned` | F | 2 |
| Archivar o desarchivar | `workspace archive/unarchive` (existe) | `archive_workspace` / `unarchive_workspace` | F | 2 |
| Dormir | `workspace sleep` (existe) | `sleep_workspace` | F | — |
| Despertar: reabrir las sesiones de las tabs dormidas | `workspace wake` (nuevo → `workspace.wake` nuevo, sobre `workspace.sleptTabs` y `createOrAttach`) | `wake_workspace` | F | 2 |
| Enfocar en la app desktop | `workspace focus` (existe) | `focus_workspace` | F | 2 |
| Vista previa de borrado: almacenamiento, dependencias, cascada | `workspace remove-preview` (nuevo → `workspace.storageImpact` + `removalDependencies` + `workspaceCascade.preview`) | `preview_workspace_removal` | R | 2 |
| Borrar workspace activo o archivado con el flujo de la UI (6.3) | `workspace remove` (ampliar `--editor-buffers save|discard`) | `remove_workspace` | F | 2 |
| Hand Off / Hand On | `workspace hand-off/hand-on` (existe) | `hand_off_workspace` / `hand_on_workspace` | F | 2 |
| Recovery y setup: inspeccionar, ejecutar setup, recuperar o cancelar el setup de una reubicación | `workspace recovery`, `workspace setup` (existe); `workspace recovery resume/cancel` (nuevo) | `get_workspace_recovery` / `run_workspace_setup` / `recover_workspace_setup` / `cancel_workspace_setup` | R / F / F / F | 2 |
| Registrar o desregistrar metadatos (reparación) | `workspace register/unregister` (existe) | `register_workspace_record` / `unregister_workspace_record` | A | 2 |
| Secciones: listar, crear, asignar (también el árbol), quitar, borrar | `workspace section …` (existe; ampliar `--tree`) | `list_sections` / `create_section` / `set_workspace_section` / `clear_workspace_section` / `remove_section` | R / F / F / F / F | 2 |
| Tags globales y asignación | `tag list/upsert/remove`, `workspace tag/untag` (existe) | `list_tags` / `upsert_tag` / `remove_tag` / `tag_workspace` / `untag_workspace` | R / F / F / F / F | 2 |
| Relación padre/hijo y vista previa de cascada | `workspace link/unlink/cascade-preview` (existe) | `link_workspaces` / `unlink_workspaces` / `preview_workspace_cascade` | F / F / R | 2 |
| Issue enlazado | `workspace issue show/link/unlink` (existe) | `show_workspace_issue` / `link_workspace_issue` / `unlink_workspace_issue` | R / F / F | 2 |

#### Tabs, terminales y perfiles de agente

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Listar tabs | `tab list` (existe) | `list_tabs` | R | — |
| Crear tab de terminal o comando | `tab create` (existe) | `create_tab` | F | 4 |
| Cerrar tab y terminar su sesión (D, M) | `tab remove --terminate` (ampliar) | `close_tab` | F | 4 |
| Renombrar tab y generar título con IA (D, M) | `tab rename`, `tab generate-title` (nuevo → `tab.rename`, `aiText.agentTitle.generate`) | `rename_tab` / `generate_tab_title` | F | 4 |
| Re-vincular agente a tab | `tab link-agent` (existe) | `link_agent_to_tab` | F | 4 |
| Terminales: listar, ver, leer, esperar, escribir | existe | existentes | R / F | — |
| Reiniciar terminal (D, M) | `terminal restart` (nuevo → `terminal.restart`) | `restart_terminal` | F | 4 |
| Terminar una sesión (Resource Manager) | `terminal terminate` (nuevo → `terminate`) | `terminate_terminal` | F | 4 |
| Purgar sesiones detenidas | `terminal prune` (existe) | `prune_terminals` | A | 4 |
| Terminal Pulse (D) | `terminal pulse show/set` (nuevo → `terminal.pulse.*`) | `get_terminal_pulse` / `configure_terminal_pulse` | R / F | 4 |
| Perfiles: listar, ver, impacto de borrado | `agent-profile list/show/removal-impact` (existe) | `list_agent_profiles` / `show_agent_profile` / `preview_agent_profile_removal` | R | 4 |
| Perfiles: crear, actualizar (incluidas reduced protections), borrar y reordenar (F2) | `agent-profile create/update/remove/reorder` (existe) | `create_agent_profile` / `update_agent_profile` / `remove_agent_profile` / `reorder_agent_profiles` | A | 4 |
| Perfil por defecto (cambio de configuración, F2) | `runtime settings set defaultAgentProfileId` | `set_default_agent_profile` | A | 4 |
| Lanzar perfil, incluida la reanudación de sesión | `agent-profile launch` (ampliar `--resume-session-id`) | `launch_agent` (ampliar `resumeSessionId`, `clientRequestId`) | F | 4 |

#### Inbox (U7)

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Destinos, preguntar, hilos, ver, esperar respuesta | existe (ampliar con origen y filtros) | `list_inbox_targets` / `ask_agent` / `list_inbox_threads` / `show_inbox_thread` / `wait_for_reply` (ampliar) | R / F / R / R / R | 5 |
| Esperar cualquier novedad del inbox | `inbox wait --inbox` (existe) | `wait_for_inbox` | R | 5 |
| Cancelar pregunta y marcar como leído | `inbox cancel/read` (existe) | `cancel_question` / `mark_thread_read` | F | 5 |
| Resumen de inboxes | `inbox list` (existe) | `list_inboxes` | R | 5 |
| Conversaciones entre agentes | `inbox conversations/conversation` (existe) | `list_agent_conversations` / `show_agent_conversation` | R | 5 |
| Purgar inbox | `inbox purge` (existe) | `purge_inbox` | A | 5 |

#### Orquestación y workflows (sin decisiones humanas)

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Tareas: listar, ver, esperar, delegar, cancelar | existe | existentes | R / F | — |
| Crear tarea, dispatch, ver o interrumpir dispatch, agent-spawn | `orchestration task-create/dispatch/dispatch-show/dispatch-interrupt/agent-spawn` (existe) | `create_task` / `dispatch_task` / `show_dispatch` / `interrupt_dispatch` / `spawn_agent` | F / F / R / F / F | 5 |
| Mensajes | existe | `send_message` / `list_messages` (ampliar `payload`, `taskId`) | F / R | 5 |
| Coordinador: iniciar, detener, ver run | `orchestration run/run-stop/run-show` (existe) | `start_coordinator` / `stop_coordinator` / `show_run` | F / F / R | 5 |
| Board, snapshot de run e inspección de tarea (D) | `orchestration board/run-snapshot/task-inspect` (nuevo → `orchestration.boardSnapshot/runSnapshot/taskInspection`) | `get_orchestration_board` / `get_run_snapshot` / `inspect_task` | R | 5 |
| Gates: listar y crear (pedir decisión al humano) | `orchestration gate-list/gate-create` (existe) | `list_gates` / `create_gate` | R / F | 5 |
| Run policy: proponer y ver | `orchestration run-policy-propose/show` (existe) | `propose_run_policy` / `show_run_policy` | F / R | 5 |
| Recuperar tarea, transferir coordinador, reset, purgar terminales | existe | `recover_task` / `transfer_coordinator` / `reset_orchestration` | A | 5 |
| Recetas: listar, ver, validar, guardar personal, exportar a proyecto | `orchestration recipes …` (existe; `export` nuevo → `workflows.previewRecipeExport/applyRecipeExport`) | `list_recipes` / `show_recipe` / `validate_recipe` / `save_personal_recipe` / `export_recipe` | R / R / R / F / F | 5 |
| Propuestas: crear, listar, estado, enviar, cancelar, reintentar cancelación, iniciar coordinador (D) | `orchestration proposals …` (nuevo → `workflows.*Proposal*`, `startCoordinator`) | `create_workflow_proposal` / `list_workflow_proposals` / `get_workflow_proposal` / `submit_workflow_proposal` / `cancel_workflow_proposal` / `start_workflow_coordinator` | F / R / R / F / F / F | 5 |
| Planes: preparar y ver | `orchestration plans prepare/show/proposal/submit-proposal` (existe) | `prepare_workflow_plan` / `show_workflow_plan` | F / R | 5 |
| Ejecución: iniciar o pausar, nuevo intento, reintentar integración, corrección (D) | `orchestration workspaces …` (existe) + `orchestration execution control/correct` (nuevo → `workflows.controlExecution/createCorrection`) | `control_workflow_execution` / `prepare_workflow_attempt` / `launch_workflow_task` / `integrate_workflow_result` / `list_workflow_integrations` / `create_workflow_correction` | F / F / F / F / R / F | 5 |
| Limpieza de recursos de workflow (D) | `orchestration cleanup preview/apply/retry/abandon/status` (nuevo → `workflows.*Cleanup*`) | `preview_workflow_cleanup` / `apply_workflow_cleanup` / `retry_workflow_cleanup` / `abandon_workflow_cleanup` / `get_workflow_cleanup` | R / A / A / A / R | 5 |

#### Automations (U5)

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Listar, con todos los filtros | `automation list` (existe) | `list_automations` (ampliar) | R | 6 |
| Ver automation, ver run y su contexto | `automation show/run-show` (existe) | `show_automation` / `show_automation_run` | R | 6 |
| Crear (activa o borrador), editar, clonar | `automation create/edit` (existe; `--request-key`, `--expected-revision`) | `create_automation` / `update_automation` / `clone_automation` | F | 6 |
| Readiness y vista previa de cron | `automation readiness/preview-schedule` (existe) | `check_automation_readiness` / `preview_automation_schedule` | R | 6 |
| Pausar (y cancelar runs), reanudar, papelera, restaurar | `automation pause/resume/trash/restore` (existe) | `pause_automation` / `resume_automation` / `trash_automation` / `restore_automation` | F | 6 |
| Purgar | `automation purge` (existe) | `purge_automations` | F | 6 |
| Ejecutar ahora con todas las opciones (sin precheck, en cola o en paralelo, continuar desde un run) | `automation run-now` (existe) | `run_automation` (ampliar) | F | 6 |
| Runs: listar, cancelar, reanudar en espera, extender, tomar el control | `automation runs/cancel/wait/extend` (existe); `automation take-over` (nuevo → `automation.takeOver`) | `list_automation_runs` / `cancel_automation_run` / `resume_automation_run` / `extend_automation_run` / `take_over_automation_run` | R / F / F / F / F | 6 |
| Plantillas, tags, exportar, importar | `automation templates/tags/export/import` (existe) | `list_automation_templates` / `upsert_automation_template` / `list_automation_tags` / `upsert_automation_tags` / `export_automations` / `import_automations` | R / F / R / F / R / F | 6 |

#### Pull requests (U6, F3)

Cubre GitHub, GitLab y Azure DevOps en todas las filas, a través de `ForgeProvider` en el runtime (sección 6.4). La única excepción son los stacks, que como en el desktop solo existen en GitHub.

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Snapshot: estado, checks, conversación, métodos de merge | `pr show` (nuevo → `mobile.pullRequest.snapshot`, multi-forja) | `get_pull_request` | R | 7 |
| Resúmenes por workspace | `pr summaries` (nuevo → `mobile.pullRequest.summaries`) | `list_pull_request_summaries` | R | 7 |
| Generar título y cuerpo con IA | `pr generate-details` (nuevo → `aiText.pullRequestDetails.generate`) | `generate_pull_request_details` | F | 7 |
| Crear PR (draft opcional) | `pr create` (nuevo → `mobile.pullRequest.create`) | `create_pull_request` | F | 7 |
| Enlazar o desenlazar | `pr link/unlink` (nuevo) | `link_pull_request` / `unlink_pull_request` | F | 7 |
| Comentar, responder, editar comentario | `pr comment/comment-edit` (nuevo) | `comment_pull_request` / `edit_pull_request_comment` | F | 7 |
| Ready o draft | `pr draft` (nuevo → `draftStatus`) | `set_pull_request_draft` | F | 7 |
| Cerrar | `pr close` (nuevo) | `close_pull_request` | F | 7 |
| Merge con los métodos de cada forja (GitHub: merge, squash o rebase; GitLab: merge o squash; Azure DevOps: noFastForward, squash, rebase o rebaseMerge) | `pr merge` (nuevo) | `merge_pull_request` | F | 7 |
| Ship Changes (scope all o staged, draft, base) más watch de seguimiento opcional | `pr ship [--follow-up-watch …]` (nuevo → `mobile.pullRequest.ship` + `pullRequestWatch.start`) | `ship_changes` (incluido el seguimiento `fixAndMerge`) | F | 7 |
| Restack (dispatch a un agente) | `pr restack` (nuevo → `pullRequest.agentDispatch` nuevo) | `restack_pull_request` | F | 7 |
| Fix Failed Checks (dispatch a un agente) | `pr fix-checks` (nuevo, mismo RPC) | `fix_pull_request_checks` | F | 7 |
| Watch and Fix: ver, iniciar, detener | `workspace pr-watch show/start/stop` (existe) | `show_pull_request_watch` / `start_pull_request_watch` (modos `fix` y `fixAndMerge`) / `stop_pull_request_watch` | R / F / F | 7 |
| Stacks (solo GitHub, igual que el desktop): ver, crear desde workspaces, enlazar, merge del stack | `pr stack show/create/link/merge` (nuevo → RPC `pullRequestStack.*` nuevo, port de Dart) | `get_pull_request_stack` / `create_pull_request_stack` / `link_pull_request_stack` / `merge_pull_request_stack` | R / F / F / F | 7 |
| Archivar o borrar el workspace tras el merge | Se reutilizan `archive_workspace` / `remove_workspace` | — | — | — |

#### Eventos y notificaciones (U8)

| Capacidad | CLI | Herramienta MCP | Nivel | Fase |
|---|---|---|---|---|
| Diario de eventos: listar y esperar con cursor | `events list/wait` (nuevo → `runtimeEvents.*` nuevo) | `list_events` / `wait_for_events` | R | 8 |
| Webhooks genéricos: listar, crear, borrar, probar | `webhook list/add/remove/test` (nuevo → API de la nube) | `list_webhooks` / `create_webhook` / `delete_webhook` / `test_webhook` | A / A / A / A (listar es A: la URL suele llevar el token del receptor) | 8 |
| Suscripción local stdio y MCP Events | Métodos de protocolo, no tools (sección 6.5) | — | — | 8 |

### 2.2 Cambios de nivel en herramientas existentes

No se mueve ninguna herramienta existente a Admin, para no romper los grants actuales (U1). `cancel_task` sigue en Full aunque sea una cancelación administrativa, y queda anotada como `destructiveHint`.

### 2.3 Excluido (impuesto por `catalog_exclusion_tests`)

| Grupo | Ejemplos (CLI o RPC) | Motivo |
|---|---|---|
| Cuenta, OAuth y MCP Control | `account *`, `mcp enable/disable/apps/revoke/status`, `mcp.settings.*`, `mcp.grants.*`, consentimiento | U4 |
| Emparejamiento mobile y dispositivos | `mobile *`, `mobile.pairing.*`, `mobile.device.*`, `mobile.settings.update` | U4 |
| Credenciales e instalación remota | `ssh-target add/remove/bootstrap*/link`, `hostLink.*` | U4 (escalado: instala sidecars y guarda credenciales) |
| Ciclo de vida del runtime | `runtime start/stop/clear/rename`, `host.restart/shutdown/process.run`, `runtimeMetadata.set` | U4 (además, cortaría la propia sesión) |
| Credenciales de proveedores y de IA | `aiAssist.chatgpt.*`, `voice.credentials.*`, `aiDictation.credentials.*` | U4 y reglas de `AGENTS.md` |
| Instalación de software en el host | `cliRegistration.install`, `agentSkill.install`, updater | U4 (escalado) |
| Configuration Sync en la nube | `configuration.*` | U4 |
| Decisiones humanas | `orchestration gate-resolve`, `run-policy-approve/reject`, decisiones, revisiones y challenges de `workflows` | U5 |
| Explorer, búsqueda, Source Control general, archivos y diffs | `git.*`, `mobile.git.*`, `workspace.files.*`, `mobile.workspaceFile.*`, `mobile.workspaceSearch.*`, `quickOpen` | U6 |
| Ciclo de vida interno del worker o del run | `orchestration check/reply/context/heartbeat/escalate/complete/worker-done/worker-help/current`, `automation context/heartbeat/complete` | Requieren identidad de terminal o run; no son acciones de un cliente externo |
| Presentación | `layout.*`, `workbenchViewPrefs.*`, tema, atajos, voz en vivo (`voice.start/stop/turn`), dictado | No son capacidades del runtime |

## 3. Modelo de permisos

### 3.1 Niveles y scopes

| Barrera | Valores | Regla |
|---|---|---|
| Runtime (MCP Control, `settings.mcp.access`) | `off` < `read` < `full` < `admin` | `allows(tool)`: Read requiere ≥ read, Execute ≥ full, Admin = admin |
| Token OAuth (grant) | `mcp:read`, `mcp:execute`, `mcp:admin` | Las herramientas Admin requieren `mcp:admin`; las Execute, `mcp:execute` |
| Call grant de la nube | `access ∈ {read, execute, admin}` | El runtime verifica que `claims.access` cubra la herramienta |

- **Concesión**: `mcp:admin` nunca entra en el default de `normalize_scope` (`cloud/src/mcp_oauth/authorize.rs:52-64`). Solo se concede si el cliente lo pide **y** el usuario marca una casilla nueva en el consentimiento, que va desmarcada por defecto. Los grants existentes conservan su `scopes` (U1).
- **Runtime**: el nivel `admin` solo se elige de forma explícita en MCP Control (desktop) o con `alera mcp enable --access admin`. Pasar de `full` a `admin` no ocurre nunca sin intervención.

### 3.2 Pertenencia a Admin (F1 opción B y F2)

Admin se reserva para la administración avanzada del runtime, la configuración de agentes y las operaciones internas sensibles:

- **Administración del runtime:** `update_runtime_settings`, `set_agent_integrations`, `consume_codex_reset_credit` y la gestión de webhooks (`create_webhook`, `delete_webhook`, `test_webhook`).
- **Configuración de agentes (F2):** `create_agent_profile`, `update_agent_profile` (incluidas reduced protections), `remove_agent_profile`, `reorder_agent_profiles` y `set_default_agent_profile`.
- **Operaciones internas sensibles:** `reset_orchestration`, `recover_task`, `transfer_coordinator`, `prune_terminals`, `apply_workflow_cleanup`, `retry_workflow_cleanup`, `abandon_workflow_cleanup`, `register_workspace_record`, `unregister_workspace_record` y `purge_inbox` (borra el historial compartido de todos los clientes; ver R10).

Todo lo demás que muta es Full, sin confirmaciones fuera del flujo de la UI (F1, U2). Eso incluye:

- borrar workspaces y proyectos;
- merge de PR y de stacks, y Watch o Ship en modo `fixAndMerge`;
- `purge_automations`;
- el CRUD de automations con activación inmediata (U5).

Con Full, los perfiles solo se listan, se consultan y se usan: `launch_agent`, `start_workspace_from_prompt`, `delegate_task` y automations que referencian perfiles existentes.

### 3.3 Cambios por capa (puntos exactos)

**Nube:**

- `cloud/src/mcp_models.rs:9-61`: `SCOPE_ADMIN`, `McpAccess::Admin`, `ToolAccess::Admin`.
- `cloud/src/mcp_oauth/authorize.rs:52-64,185-198`: admin no entra en el default.
- `consent.rs:106-145,282-290`: casilla admin desmarcada y etiqueta del runtime.
- `metadata.rs:48,58`, `clients.rs:244` (scopes soportados) y `api_models.rs:86`.
- `mcp_gateway.rs:192-219`: exigir `mcp:admin` y nivel del runtime `admin`.
- Migración `0024_mcp_admin.sql`: CHECK de `runtimes.mcp_access` y de `mcp_calls.access`; subir `migrations.rs:13-14`.

**Edge:**

- `protocol.ts:4` (`MCP_SCOPES`).
- `tools.ts:4,31` (`ToolAccess` y validador; catálogo v2).
- `tool_call.ts:190-196` (scope admin).
- `relay_authorization.ts:18,261` y `relay_calls.ts:83` (aceptar `admin`).

**Runtime:**

- `mcp_settings.rs:15-49`, `mcp_tools/mod.rs:31-43,120-135`.
- `relay_mcp.rs:224-235`, `relay_runtime_auth.rs:286`, `server/mcp_requests.rs:70-72`.
- CLI: `cli/mcp.rs:34-52` (`--access off|read|full|admin`, con `--read-only` como alias) y `mcp_commands.rs:38-41,283-290`.

**Desktop:**

- `mcp_access/domain/mcp_access_settings.dart:7-19` (`admin`).
- `presentation/mcp_access_control_group.dart:43-60,161-171` (cuarto segmento con aviso).
- `domain/mcp_grant.dart:36` (`canAdmin`) y `mcp_connected_apps_group.dart:149` (chip).

**Documentación:** `docs/remote-mcp.md`.

## 4. Arquitectura

### 4.1 Principios

1. **Una herramienta MCP equivale a un comando CLI `--json`.** Se mantiene el invariante de `mcp_tools/mod.rs`, así que el CLI gana la misma paridad. Los comandos "nuevos" son clientes finos de RPC del host que ya existen o que se crean.
2. **La lógica vive en el runtime host o en `alera-core`.** Las herramientas no reimplementan reglas. Lo que hoy solo existe en Dart (pipeline From Prompt, prompts de Restack y Fix Checks, stacks) se porta a Rust, y la GUI pasa a consumirlo, detectándolo por capability.
3. **Operación larga, respuesta asíncrona.** Todo lo que pueda superar unos 40 s devuelve un `operationId` persistido (From Prompt, clone, ship), y se sigue con `get_*` o `wait_*` (≤ 50 s).
4. **Todo es aditivo.** Hay capabilities nuevas y no cambian las versiones estrictas de los protocolos terminal-host y mobile (`AGENTS.md`).

### 4.2 Evolución de `mcp_tools`

- `ToolAccess::{Read, Execute, Admin}`.
- `ToolSpec` añade:
  - `idempotent: bool` (`annotations.idempotentHint`)
  - `structured: bool` (el executor convierte un stdout JSON objeto en `structuredContent` y conserva el `text`)
  - `client_request_flag: Option<&'static str>` (con qué flag del CLI se pasa `clientRequestId`)
  - `output_schema: Option<fn() -> Value>` (MCP `outputSchema`, para versiones ≥ 2025-06-18)
- El catálogo se divide por dominio en `mcp_tools/catalog/{runtime,projects,workspaces,prompt_workspace,tabs,agents,inbox,orchestration,workflows,automations,pull_requests,events}.rs`, para cumplir el ratchet de máximo de líneas (`dart run tool/quality/check_max_lines.dart`).
- `CATALOG_VERSION = 2`. El edge acepta 1 y 2 (`edge/src/mcp/tools.ts` `loadCatalog`).
- Executor (`executor.rs`):
  1. Exporta `ALERA_MCP_ORIGIN` (JSON `{transport, clientId, clientName, grantId?, callId}`). Remoto: claims del call grant (`relay_mcp.rs:189-242` ya tiene `client_name`; se añaden `client_id` y `grant_id` a los claims). Local: `clientInfo` de `initialize`, con `transport: "local"`. No entra en `CONTEXT_VARIABLES`: es un contexto nuevo y explícito.
  2. Mapea los errores del CLI al modelo de la sección 4.6.
  3. Las herramientas `structured` devuelven `structuredContent`.
- Servidor stdio (`stdio_server.rs`): añade `resources`, `subscribe`, `progress` y la negociación `2026-07-28` (sección 6.5).

### 4.3 RPC nuevas o ampliadas del runtime host

| RPC | Propósito | Capability |
|---|---|---|
| `workspace.promptStart.{start,get,wait,list,cancel,retryLaunch}` | Servicio From Prompt (6.1) | `promptWorkspaceServiceV1` |
| `aiText.workspaceIdentity.generate` (ampliar con `projects` y `infer: ["project"]`) | Inferencia de proyecto | `aiAssistWorkspaceIdentityV2` |
| `workspace.wake` | Reabrir sesiones dormidas | `workspaceWakeV1` |
| `workspace.bufferGuard.*` (ampliar con `resolution: save|discard`) y evento `checkoutBuffersSaveRequested` | Borrado con buffers sucios "Save" | `checkoutBufferSaveV1` |
| `workspace.storageImpact` (reenviar a host remoto) | Corrige el bloqueo del borrado remoto (6.3) | — (fix) |
| `pullRequest.agentDispatch {workspaceId, kind: restack|fixFailedChecks, target}` | Prompts únicos en Rust | `pullRequestAgentDispatchV1` |
| `pullRequestStack.{get,create,link,merge}` | Port de `github_stack_actions.dart` (solo GitHub, como el desktop) | `pullRequestStacksV1` |
| `mobile.pullRequest.*` sobre `ForgeProvider` (GitHub, GitLab y Azure DevOps) | Paridad multi-forja (F3) | `pullRequestForgesV1` (lista de proveedores soportados) |
| `pullRequestWatch.*` (ejecución en el runtime para las tres forjas) | Watch and Fix multi-forja | `pullRequestWatchExecutionV2` |
| `runtimeEvents.{list,wait}` | Diario de eventos (6.5) | `runtimeEventsV1` |
| `inbox.ask` (aceptar `externalOrigin` solo de clientes `Local`) e `inbox.threads` (filtros `originClientId` y `own`) | Atribución (6.4) | `inboxOriginV1` |
| `mutationReceipts` (interno) | Idempotencia genérica (4.5) | — |

Toda RPC nueva se añade a la lista de capabilities del control file (`control_file.rs:79-154`) y a `status.get` (`host_status.rs:70`). La allowlist mobile (`mobile_gateway_surface.rs`) y la política del hub (`hub_reverse_policy.rs`) solo se tocan donde la GUI mobile lo necesite: From Prompt y PR dispatch.

### 4.4 Esquemas de llamada (herramientas clave)

Convenciones comunes:

- todos los objetos llevan `additionalProperties: false`
- los textos largos viajan por stdin
- `clientRequestId`: string de 8 a 128 caracteres, opcional en toda mutación

`start_workspace_from_prompt` (F):

```json
{
  "prompt": "string (1..65536, requerido)",
  "projectId": "string?",
  "profile": "string? (id prof_… o nombre; por defecto el del runtime)",
  "mode": "auto | worktree | projectCheckout (default auto)",
  "sourceBranch": "string?",
  "hostId": "string?",
  "parentWorkspaceId": "string?",
  "issueUrl": "string?",
  "section": "auto | none | {\"id\"} | {\"name\"} (default auto)",
  "clientRequestId": "string?"
}
```

Resultado `structuredContent`:

```json
{
  "operationId": "pws_…",
  "status": "running|needsInput|completed|failed|cancelled",
  "phase": "resolvingProject|generatingIdentity|checkingBranch|creatingWorkspace|assigningSection|preparingSetup|launchingAgent|startingSetup|done",
  "candidates": [{ "projectId": "…", "name": "…", "reason": "…" }],
  "workspace": { "id": "…", "name": "…", "branch": "…", "sectionId": "…|null", "projectId": "…" },
  "agent": { "tabId": "…", "terminalHandle": "…", "profileId": "…" },
  "setup": { "tabId": "…|null", "status": "none|running|deferred" },
  "error": { "code": "…", "message": "…", "retryable": true },
  "cursor": 0
}
```

`wait_for_workspace_start` (R): `{operationId, timeoutSeconds ≤ 50}` y devuelve lo mismo.

`remove_workspace` (F):

```json
{
  "workspaceId": "string",
  "branch": "delete | keep (default: delete si la rama es borrable, como el botón Remove; si no, keep)",
  "editorBuffers": "save | discard (default save)",
  "clientRequestId": "string?"
}
```

Resultado: `{removed, workspaceId, branch: {name, deleted, retainedReason?}, pausedAutomations[], unlinkedChildren[], closedSessions}`.

`ask_agent` (F, ampliado): añade `clientRequestId`. Resultado: `{questionId, threadId, recipient, origin: {clientId, clientName, transport}}`.

`wait_for_inbox` (R):

```json
{
  "after": "int?",
  "scope": "own | all (default own)",
  "threadId": "string?",
  "timeoutSeconds": "int ≤ 50"
}
```

Resultado: `{outcome: message|timeout, messages[], cursor, truncated}`, y cada mensaje lleva `origin`, `isOwn` y `threadId`.

`list_inbox_threads` (R, ampliado): `{originClientId?, scope: own|all (default all), status?, workspaceId?, limit?, before?}`. Cada hilo lleva `origin` e `isOwn`.

`ship_changes` (F):

```json
{
  "workspaceId": "string",
  "baseBranch": "string",
  "draft": "boolean?",
  "scope": "all | staged",
  "followUpWatch": { "mode": "fix | fixAndMerge", "profile": "string?", "handle": "string?", "checks": true, "comments": true, "conflicts": true },
  "clientRequestId": "string?"
}
```

Tras F1, `fixAndMerge` es Full, así que basta una sola herramienta. Funciona con GitHub, GitLab y Azure DevOps; el `baseBranch` y los métodos de merge se validan contra el proveedor.

`wait_for_events` (R):

```json
{
  "after": "int?",
  "kinds": ["inbox.reply", "…"],
  "workspaceId": "string?",
  "timeoutSeconds": "int ≤ 50"
}
```

Resultado: `{events[], cursor, truncated}`.

### 4.5 Idempotencia

| Caso | Mecanismo |
|---|---|
| Lanzamientos (`launch_agent`, From Prompt, `start_agent_workspace`) | `agentProfile.launchIdempotent` con `clientMutationId` = `clientRequestId`, o derivado del `operationId` en From Prompt |
| From Prompt | `promptWorkspaceOperations.requestId UNIQUE`: misma clave, misma operación |
| Automations | `--request-key` (ya existe) |
| Resto de mutaciones | Tabla nueva `mcpMutationReceipts(scope, key, tool, argumentsHash, status, resultJson, createdAt)` con TTL de 24 h, **en el runtime host** (C5). RPC `mutationReceipts.claim/complete`: el claim es atómico, una clave en curso devuelve `conflict` reintentable y una clave completada devuelve el resultado guardado. Misma clave con argumentos distintos: `idempotency_conflict` |
| Esperas | Ya son idempotentes por cursor |

### 4.6 Modelo de errores

El resultado de la herramienta lleva `isError: true` y `structuredContent.error = {code, message, retryable, details?}`.

Códigos estándar:

- `invalid_argument`, `not_found`, `conflict`, `idempotency_conflict`
- `capability_missing` (el runtime necesita actualizarse), `tool_unavailable`
- `access_denied`, `runtime_read_only`, `runtime_offline`
- `timeout_pending` (incluye `operationId`), `ai_assist_unavailable`
- `provider_unsupported` (función que la forja no tiene en Alera, como los stacks fuera de GitHub)
- `provider_unavailable` (falta `gh`, `glab` o `az`, o no hay autenticación en el host del checkout)
- `blocked` (bloqueos de la UI, como "Cleanup Unavailable", con `details.blockers`)
- `needs_input` (con candidatos)
- `scope_required` (C6): una herramienta Admin llamada sin `mcp:admin` devuelve el error con instrucciones de reconectar la app y marcar Admin en el consentimiento. Para clientes que hagan step-up, el edge responde además `403 insufficient_scope` con `WWW-Authenticate: … scope="mcp:read mcp:execute mcp:admin"`

Los mensajes de la UI se reutilizan literalmente, y el CLI emite siempre JSON de error con `--json`.

## 5. Seguridad

1. **Doble barrera por nivel** (3.1). Un test en cada capa: nube (contratos), edge (bun) y runtime (`relay_mcp_tests`).
2. **Exclusiones y decisiones humanas**: `catalog_exclusion_tests` recorre el catálogo y falla si alguna `Invocation` usa los grupos `account`, `mcp`, `mobile` o `ssh-target add/remove/bootstrap/link`, `runtime start/stop/clear/rename`, `gate-resolve`, `run-policy-approve/reject`, verbos de decisión de `workflows`, `git`, `files` o `search`.
3. **Atribución de origen confiable**: el host acepta `externalOrigin` solo de clientes `ClientKind::Local` (el CLI hijo). Mobile no puede falsificarlo. Se valida la forma y el tamaño (≤ 16 KiB, que ya es `INBOX_EXTERNAL_META_MAX_BYTES`).
4. **Política de payloads de eventos**: solo IDs, estado y nombres de proyecto o workspace, igual que la regla de push de `AGENTS.md`. Nunca prompts, salida, código ni texto de orquestación. Un test valida cada tipo de evento contra una lista blanca de claves.
5. **Webhooks**:
   - HTTPS:443, DNS restringido a IPs públicas y fijado, sin redirecciones.
   - Challenge firmado al registrar, Standard Webhooks (`webhook-id`, `webhook-timestamp`, `webhook-signature`).
   - Secreto `whsec_` cifrado en reposo con una clave de la nube (`WEBHOOK_SECRET_KEY`, rotable).
   - Respuestas limitadas a 16 KiB y 10 s por intento.
   - Se reaprovecha el diseño de EducUp como referencia, no como dependencia.
6. **Configuración de agentes (F2)**: toda mutación de perfiles (crear, editar, incluidas reduced protections, borrar, reordenar, perfil por defecto) es Admin. Con Full solo se listan, se consultan y se lanzan perfiles existentes, y las automations Full solo referencian perfiles existentes. Limitación conocida: `write_terminal` y `create_tab --command` (Full) siguen permitiendo ejecutar comandos arbitrarios, incluido un agente con permisos reducidos; esto no cambia el riesgo existente.
7. **`write_terminal`** sigue en Full (riesgo aceptado, ya existente) y queda documentado en la UI de MCP Control.
8. **Auditoría**: `mcp_calls.access` admite `admin`. Se conserva la política de solo metadatos.
9. **Límites**: `MCP_LIMITER` actual. El runtime mantiene 4 llamadas concurrentes; las esperas no cuentan para el límite de mutaciones (`MAX_CONCURRENT_CALLS` se separa en lecturas y escrituras).

## 6. Diseños detallados

### 6.1 Servicio New Workspace from Prompt (U9)

**Persistencia** (`alera-core`, patrón de `projectCloneJobs` y `workflowLaunches`): tabla `promptWorkspaceOperations` con estas columnas:

- `id`, `requestId UNIQUE`, `status`, `phase`, `message`, `error`
- `projectId?`, `profileId`, `mode`, `sourceBranch?`, `hostId?`, `parentWorkspaceId?`, `issueUrl?`, `sectionPolicy`
- `prompt` en claro mientras la operación está activa (C4: `runtime.sqlite` no está cifrado, igual que el resto del store); al llegar a un estado final se sustituye por `promptHash`
- `candidatesJson?`, `workspaceId?`, `agentTabId?`, `setupTabId?`, `clientMutationId`, `attempts`, `origin`, `createdAt`, `updatedAt`

Se añaden reconciliación al arranque (`reconcile_interrupted_prompt_starts`), un mapa de cancelación en memoria, el evento `promptWorkspaceOperationsChanged {id}` y un guard en `schedule_shutdown_if_idle`.

**Algoritmo** (host). Reproduce `PromptWorkspacePipeline`, más las mejoras acordadas:

1. **Proyecto**:
   - Si viene `projectId`, se usa.
   - Si solo hay uno, ese.
   - Si no, una llamada de identidad ampliada que incluye proyectos (nombre y ruta, como mucho 50, recortados como hoy las secciones) y pide `project`. Se valida sin distinguir mayúsculas.
   - Si responde "unknown", algo inválido o hay ambigüedad: `needsInput` con candidatos ordenados por actividad (`workspaceActivity`). El cliente repite con `projectId` y una `clientRequestId` nueva.
   - La identidad (nombre, rama y sección) se genera en esa misma llamada cuando el proyecto queda resuelto. Si no, en una segunda llamada.
2. **Perfil**: el explícito, si no `runtimeSettings.defaultAgentProfileId`, si no el primero en orden (igual que `_defaultAgentProfile`).
3. **Modo**:
   - `projectCheckout` y `worktree` se respetan.
   - `auto`: worktree si el proyecto es repo Git (aislamiento para agentes desatendidos); projectCheckout si no lo es (como la UI cuando no hay Git).
   - La UI, al migrar, envía siempre un modo explícito (su default actual es `projectCheckout`), así que la equivalencia con la UI se mantiene.
4. **Rama origen**: la explícita, si no `preferred_source_branch` (configuración del proyecto), si no la rama por defecto del repo, si no la rama actual de la carpeta del proyecto. Así lo hace hoy `managed_workspace.rs:139-141` para el primer paso.
5. **Identidad**:
   - `generate_workspace_identity` con `autoAssignSection = (section == auto)`.
   - Fallback "Others": sin `sectionId` (`ai_assist_workspace_identity.rs:151-166`).
6. **Colisión**:
   - Ramas de workspaces activos del mismo host, más `branchExists` local o el catálogo del host remoto.
   - Un reintento de identidad con el texto actual de la UI y, después, un sufijo determinista `-2…-9`. Es una mejora explícita, y la UI la hereda al migrar.
7. **Crear**: `createManaged` o `createShared` con `deferSetup: true` e `issueUrl`; enlazar el padre (si falla, aviso, como `_createWorkspace`).
8. **Sección**: `workspaceSection.setForWorkspace` en modo best-effort, guardando el aviso.
9. **Lanzar**: `agentProfile.launchIdempotent` con `clientMutationId` derivado de `id`.
10. **Setup**: el host crea la tab "Setup" con el `deferredSetupCommand` y la arranca (`terminal.create` con spawn), igual que mobile (`deferred_workspace_setup_launcher.dart`). Desktop y mobile la muestran al sincronizar tabs. La GUI migrada no abre su propia tab Setup cuando la operación trae `setupTabId` (C7).
11. **Fallo después de crear**: `failed` con `workspaceId` y `retryable`. `retryLaunch` relanza con el mismo `clientMutationId` y nunca recrea el workspace (equivalente al snapshot `created` de la UI).
12. **Eventos**: `workspace.start.state` en cada cambio de estado.

**Sin AI Assist** (C3): igual que la UI, la operación falla en la fase `generatingIdentity` con `ai_assist_unavailable` y el mensaje del host ("AI Assist is disabled."). No hay identidad determinista. Para crear con nombre y rama explícitos se usa `start_agent_workspace` o `create_workspace`.

**CLI**: `alera workspace prompt-start run|show|list|wait|cancel|retry-launch`. `run` admite `--wait <seg>`. Además, `workspace start`:

- deja de exigir `--source-branch` y delega en el host
- envía `autoAssignSection` cuando no hay `--section`
- usa `deferSetup`
- reintenta en caso de colisión

Esto corrige D2 a D6 de la auditoría.

**Migración de la GUI**: si el runtime anuncia `promptWorkspaceServiceV1`, desktop (`background_setup_jobs.dart:100-260`) y mobile (`mobile/.../prompt_workspace_pipeline.dart`) delegan en el servicio y observan su progreso por el evento. Si no, siguen con el pipeline actual. El formulario no cambia.

### 6.2 Atribución en el buzón compartido (U7)

- **Origen**: `external_meta.origin = {surface: "mcp", transport: "remote"|"local", clientId, clientName, grantId?}`, extraído de `ALERA_MCP_ORIGIN`. El inbox sigue siendo `ext:mcp` (compartido).
- **Banner para el agente** (`message_formatter.rs:75-90`): "External question from ext:mcp via ChatGPT (MCP)". La respuesta conserva el hilo, y el origen del hilo identifica al destinatario de la respuesta.
- **Filtros**: `scope=own` compara `origin.clientId` con el del llamador. `isOwn` se calcula en el CLI con `ALERA_MCP_ORIGIN`.
- **Defaults**:
  - `list_inbox_threads` usa `all` (historial compartido visible) con `isOwn` y `origin`.
  - `wait_for_inbox` usa `own`, para no reaccionar a respuestas ajenas.
  - `wait_for_reply` y `show_inbox_thread` funcionan con cualquier hilo.
- **Hilos antiguos** (sin origen): `origin: null` e `isOwn: false`.
- **Mobile y desktop** muestran el origen en la UI del inbox (aditivo, `external_origin_suffix`).

### 6.3 Borrado de workspace con la semántica de la UI (U3)

`remove_workspace` ejecuta en el CLI (`workspace remove` ampliado) la secuencia del lanzador desktop (`workspace_removal_launcher.dart:14-196`):

1. **Rama**: `canDeleteBranch` = no es main, no es una rama reutilizada y no está vacía. Con `branch` sin indicar: `delete` si es borrable (el default del botón Remove), si no `keep`. El borrado es seguro: el servidor conserva las ramas no fusionadas o protegidas, igual que la UI, y el resultado informa `retainedReason`.
2. **Dependencias**: `workspace.removalDependencies`. Si existen, se pausan con `cancel-active` y se esperan hasta 30 s. Equivale a aceptar "Pause And Continue", y la confirmación es la del cliente MCP (U2).
3. **Almacenamiento**: `workspace.storageImpact {closeSessions: true}`. Si hay bloqueos (salvo los de automations que se van a pausar), devuelve un error `blocked` con `blockers`, igual que "Cleanup Unavailable". Hay que corregir el reenvío a hosts remotos, porque hoy bloquea el borrado remoto desde desktop.
4. **Buffers sucios de editor**: `workspace.bufferGuard`:
   - `editorBuffers = discard`: se descartan.
   - `save` (default): el host emite `checkoutBuffersSaveRequested`, los clientes guardan y responden; si un cliente no lo soporta o falla el guardado, el error es `blocked` (como "Save failure aborts" en la UI).
5. **Cambios git sin commitear**: semántica de la UI, es decir, se eliminan con el worktree (`remove_worktree(force=true)`). La descripción de la herramienta lo advierte con el texto de la UI: "Unsaved changes will be lost".
6. **Borrar**: `removeManaged` o `removeShared` con `closeSessions: true` y `deleteBranch`. Los hijos quedan desenlazados (`workspace_retirement.rs`).

El mismo flujo vale para workspaces archivados. `remove_project` sigue el lanzador desktop: dependencias, pausa y `project.remove`. Nunca borra archivos, y si hay workspaces en SSH devuelve el error del servidor.

### 6.4 Grupo PR multi-forja (U6, F3)

**Estado actual (verificado):**

- El runtime implementa las acciones de PR solo para GitHub, vía `gh`: `mobile.pullRequest.*` en `mobile_pull_request_actions.rs`, `mobile_pull_request_requests.rs`, `mobile_pull_request_ship.rs` y `mobile_pull_request_summaries.rs`.
- Para otros proveedores devuelve `unsupported` (`mobile_pull_request_requests.rs:75-95`, `actions.rs:455-470`).
- GitLab y Azure DevOps existen solo en Dart (`lib/src/features/pull_requests/infra/gitlab_*`, `azure_devops_*`), con `glab` y `az repos pr`.
- La ejecución de Watch and Fix en el runtime (`pullRequestWatchExecutionV1`) solo cubre GitHub; el desktop vigila las otras forjas en Dart.
- Los stacks son exclusivos de GitHub también en el desktop.

**Diseño:**

1. **`ForgeProvider` en el runtime** (Rust; módulo nuevo `pull_request_forges/` en `alera-cli`, o en `alera-core` si mobile o desktop lo necesitan vía FRB). Trait con operaciones:
   - `detect`, `auth_status`, `snapshot` (estado, checks o pipelines, comentarios e hilos, métodos de merge)
   - `summaries`, `create`, `link_validate`, `comment`, `comment_update`
   - `merge(method)`, `set_draft`, `close`, `merge_methods`
   - `head_sha` (para `--match-head-commit` o su equivalente)
   - Las implementaciones son `GitHubProvider` (lo actual, movido detrás del trait), `GitLabProvider` (`glab`) y `AzureDevOpsProvider` (`az repos pr`, `az pipelines`).
   - La detección del proveedor reutiliza la configuración del proyecto (`projectConfig` › proveedor de PR) y el remote, igual que el desktop.
2. **Reutilización del desktop "cuando proceda":**
   - La lógica de comandos, flags, parseo y mapeo de estados se porta 1:1 desde `gitlab_forge_provider.dart`, `gitlab_review_comments.dart`, `azure_devops_forge_provider.dart` y `azure_devops_review_comments.dart`, y los equivalentes de acciones.
   - Las respuestas reales de `glab` y `az` que usan las pruebas Dart se exportan como **fixtures compartidas** (`test/fixtures/forges/…`) y alimentan las pruebas Rust, para detectar deriva entre las dos implementaciones.
   - El desktop conserva su implementación Dart (sin migración obligatoria). Su adopción del runtime queda como mejora posterior por capability.
3. **Métodos de merge por forja:**
   - GitHub: `merge`, `squash`, `rebase`.
   - GitLab: `merge`, `squash` (con `--squash`; rebase solo si el proyecto lo permite).
   - Azure DevOps: `noFastForward`, `squash`, `rebase`, `rebaseMerge` (`az repos pr update --merge-strategy`, auto-complete o complete).
   - `merge_methods` devuelve los permitidos para la configuración del repo; un método no admitido da `invalid_argument`.
4. **Draft:** GitHub `gh pr ready [--undo]`; GitLab `glab mr update --draft/--ready`; Azure `az repos pr update --draft true/false`.
5. **Checks:** GitHub `gh pr checks`; GitLab pipelines del MR (`glab ci`, API); Azure policies y builds (`az repos pr policy list`, `az pipelines runs`). Todo se normaliza al modelo `checks[]` del snapshot actual.
6. **Ship** (`mobile.pullRequest.ship`): las partes git (fetch, rama `ship/<slug>`, stage, commit con IA y push) no cambian. Solo el paso de crear el PR y enlazarlo pasa por `ForgeProvider`. Requiere AI Assist, como hoy.
7. **Watch and Fix** (`pull_request_watch_runtime.rs`, `pull_request_watch_evaluation.rs`):
   - La evaluación (checks fallidos, conflictos, hilos sin resolver) y el merge de `fixAndMerge` pasan por `ForgeProvider`.
   - Se anuncia `pullRequestWatchExecutionV2` con la lista de proveedores. Así el desktop deja de vigilar en Dart las forjas que el runtime ya cubre y no hay doble dispatch, respetando la regla de `AGENTS.md` (Pull Request Watch).
8. **Restack y Fix Failed Checks:**
   - RPC `pullRequest.agentDispatch`, independiente del proveedor.
   - Los prompts se trasladan a una fuente única en Rust (hoy están duplicados en `lib/` y `mobile/`).
   - Destino: `handle`, `tabId` o `profileId`.
   - Desktop y mobile lo adoptan por capability.
9. **Stacks:** port de `github_stack_actions.dart` y `workspace_pull_request_stack_actions.dart` (`gh stack`, requiere la extensión `gh-stack`, que se detecta). Solo GitHub, igual que el desktop; con otras forjas, `provider_unsupported` con ese motivo.
10. **Remotos:** el hub ya reenvía `mobile.pullRequest.*` al host del checkout (`remote_pull_request_routing.rs`). `glab` o `az` deben estar instalados y autenticados **en el host que posee el checkout**; si faltan, el error es `provider_unavailable` y se indica qué CLI instalar y autenticar.

### 6.5 Eventos y notificaciones (U8)

**Fuente única: el diario de eventos del runtime.**

- Tabla `runtimeEvents(seq INTEGER PK AUTOINCREMENT, id TEXT UNIQUE, kind, workspaceId?, projectId?, dataJson, occurredAt, forwardedAt?)`, con retención de 7 días.
- Se escribe en los mismos puntos que hoy encolan push (`push_delivery.rs`; llamadas en `orchestration_requests.rs`, `coordinator_*`, `pty_events.rs`, `session_termination.rs`, `automation_*`), **antes** del gate de ajustes de push móvil (C2), y en las nuevas transiciones (From Prompt, estado de tareas, watch de PR, ciclo de vida de workspaces).
- El push móvil actual no cambia.

**Catálogo de eventos v1** (solo IDs y estado):

| `kind` | `data` |
|---|---|
| `inbox.reply` | `inbox, threadId, questionId, messageId, originClientId?` |
| `inbox.question.status` | `questionId, threadId, status` |
| `agent.status` | `workspaceId, tabId, sessionId, state (waiting|blocked|done)` |
| `terminal.exit` | `workspaceId, tabId, sessionId, exitCode` |
| `orchestration.task.state` | `taskId, runId?, state` |
| `orchestration.gate.created` | `gateId, taskId, runId?` |
| `orchestration.escalation` | `taskId, runId?` |
| `automation.run.state` | `automationId, runId, status` |
| `workspace.start.state` | `operationId, status, phase, workspaceId?` |
| `workspace.lifecycle` | `workspaceId, action (created|archived|unarchived|slept|woken|removed)` |
| `pullRequest.watch` | `workspaceId, number, action (dispatched|merged|stopped)` |

Sobre (envelope) común: `{eventId, seq, kind, runtimeId, occurredAt, data}`.

**Mecanismos:**

1. **Polling robusto (todos los clientes)**:
   - `list_events` y `wait_for_events` (cursor = `seq`; `truncated` si el cursor es anterior a la retención).
   - `wait_for_inbox` y `wait_for_reply` con atribución.
   - Las instrucciones del servidor MCP explican el bucle con el cursor.
2. **Suscripciones locales (stdio)**:
   - `capabilities.resources = {subscribe: true}`.
   - Recursos `alera://events`, `alera://inbox/ext:mcp`, `alera://inbox/thread/<id>` y `alera://workspace-start/<id>`.
   - `resources/read` devuelve el estado JSON y `notifications/resources/updated` se emite al llegar eventos.
   - `notifications/progress` en las herramientas largas si llega `progressToken`.
   - Requiere que `mcp serve` mantenga una conexión de eventos con el host: un modo "listen" en `RuntimeHostRpcClient`, que hoy descarta los eventos en `runtime_host_client.rs:289-291`.
   - Con `2026-07-28`, se implementa `subscriptions/listen` sobre la misma fuente.
3. **Reenvío a la nube**:
   - El runtime envía `runtimeEvents` con `forwardedAt IS NULL` a `POST /v1/runtime/domain-events` (endpoint nuevo, token del runtime, scope nuevo `events:send`), en lotes, con reintentos y marcando `forwardedAt`.
   - Solo cuando la nube indica que hay suscripciones activas (webhook o MCP Events) para ese runtime (C1). La respuesta del endpoint y un `GET /v1/runtime/event-subscriptions` ligero devuelven `activeSubscriptions`; con 0, el runtime deja de reenviar y conserva el diario local. Activar MCP Control no abre por sí solo un flujo de datos nuevo hacia la nube.
   - Es idempotente por `eventId`.
4. **Webhooks genéricos (nube)**:
   - Tablas `event_subscriptions(id, account_id, runtime_ids[], kinds[], target_kind webhook|mcp_events, callback_url, secret_enc, status, refresh_before, owner_grant_id?, created_at)`, `domain_events(account_id, runtime_id, event_id UNIQUE, kind, data, occurred_at)` (retención de 24 h) y `event_deliveries(subscription_id, event_id, status, attempts, next_attempt_at, lease_until, last_error)`.
   - Un worker en la nube (bucle como `maintenance.rs`, claim con `FOR UPDATE SKIP LOCKED` y lease de 45 s) firma y entrega.
   - Reintentos exponenciales de 5 s a 15 min (12 intentos). `410` detiene la suscripción y `413` deja la entrega como muerta.
   - Gestión desde Settings › Integrations › Webhooks (desktop), CLI `alera webhook …` y MCP (Admin).
5. **OpenAI MCP Events (detrás de una flag, con prueba real obligatoria, F4)**:
   - **Requisitos publicados por OpenAI** ([MCP Events](https://developers.openai.com/plugins/build/mcp-events), consultado el 2026-10-10):
     - Work chats en ChatGPT web, o en el desktop con Cloud seleccionado.
     - "Workspace controls for plugins and event-triggered tasks apply".
     - El servidor debe configurarse "in your plugin".
     - Protocolo `2026-07-28` con `events` en las capabilities de `server/discover`.
     - `events/list`, `events/subscribe` y `events/unsubscribe` en el mismo endpoint autenticado que las tools.
     - Entrega solo por webhook firmado con Standard Webhooks; la verificación del callback falla con `-32015`.
     - Hay que hacer "Rescan" del servidor cuando cambian tools o eventos.
     - La página **no** aclara si un conector MCP ya conectado cuenta como plugin, ni qué plan de ChatGPT hace falta. Por eso no se supone nada: lo verifica 8.0.
   - **8.0 Verificación de requisitos** (antes de implementar 8e; idealmente al inicio del proyecto). Con la integración de Alera ya conectada en ChatGPT:
     1. Confirmar el tipo de cuenta o workspace y que existen Work chats y los controles de plugins y tareas activadas por eventos.
     2. Comprobar si la conexión actual figura como plugin (página de plugin, sección "Tools and events") o si hay que crear o convertir un plugin.
     3. Hacer Rescan y registrar qué métodos y qué versión de protocolo envía ChatGPT al edge (métricas y logs de metadatos de `/v1/mcp`, sin cuerpos).
     4. Comprobar qué scopes y token usa al llamar `events/*`.
     5. Comprobar si ChatGPT permite crear una tarea activada por eventos sobre esa conexión.
     - El resultado es un acta con cada requisito cumplido o faltante y los pasos de configuración exactos. Si falta algo que no depende de Alera (plan, permisos de workspace), se informa como bloqueo externo y se sigue con 8a-8d.
   - **Implementación (8e)**:
     - El edge negocia `2026-07-28` sin romper `initialize` en las versiones anteriores.
     - `server/discover` con `capabilities.events`; `events/list` con los tipos del catálogo v1 y su `payloadSchema`; `events/subscribe` y `events/unsubscribe`, ligados al grant y revalidados en cada entrega.
     - Las suscripciones se guardan en `event_subscriptions` con `target_kind = mcp_events` y se detienen al revocar el grant.
     - Mismo worker, cursor de reanudación de 24 h, `refreshBefore` y `truncated`.
     - Flag `MCP_EVENTS_ENABLED` (edge y nube), apagada por defecto.
   - **8f Prueba real de extremo a extremo (obligatoria)**, con la integración conectada:
     1. Rescan.
     2. En un Work chat, pedir a ChatGPT que se suscriba a `inbox.reply` filtrado por un `threadId` creado con `ask_agent`.
     3. Verificar el challenge firmado y la suscripción guardada.
     4. El agente responde con `orchestration reply`.
     5. Callback firmado con 2xx.
     6. ChatGPT ejecuta la tarea y continúa en el chat llamando a `show_inbox_thread` o `wait_for_reply`.
     7. `events/unsubscribe` detiene la entrega.
     8. Repetir tras reiniciar el runtime y con un grant revocado.
     - **Criterio go:** continuación observable en el chat en menos de 2 minutos en 3 de 3 intentos. **No-go:** la flag sigue apagada, el acta documenta la causa y el polling con cursor queda como camino principal (ya validado en 8a).

## 7. Compatibilidad y migraciones

| Ámbito | Cambio | Compatibilidad |
|---|---|---|
| Protocolo MCP | Añadir `2026-07-28` (edge y stdio): `server/discover` y métodos de eventos; se conservan `2025-11-25`, `2025-06-18` y `2025-03-26` | Los clientes antiguos siguen igual |
| Catálogo | v2; el edge acepta v1 y v2 | Un runtime antiguo responde `tool_unavailable` con "Update Alera" (ya existe) |
| Orden de despliegue | 1) runtime (release); 2) nube (migraciones y endpoints); 3) edge (catálogo v2, admin, eventos) | El edge puede listar herramientas que un runtime antiguo no tiene: error claro |
| Runtime store | `ensure_column` y esquemas `IF NOT EXISTS`: `promptWorkspaceOperations`, `runtimeEvents`, `mcpMutationReceipts` | Hacia adelante sin versión; las tablas nuevas se ignoran en un downgrade |
| Nube (Postgres) | `0024_mcp_admin.sql` (CHECK), `0025_domain_events.sql` (`domain_events`, `event_subscriptions`, `event_deliveries`, scope `events:send`) | Aditivo; `REQUIRED_SCHEMA_MIGRATION_VERSIONS` se actualiza |
| CLI | Flags nuevos aditivos. `workspace start` gana defaults y deja de exigir `--source-branch` (relaja una validación) | Sin rupturas |
| GUI | Migración por capability (From Prompt, PR dispatch, stacks, buffer save, watch multi-forja) | Fallback a la ruta actual con hosts antiguos |
| Forjas (F3) | El runtime usa `gh`, `glab` y `az` (con la extensión `azure-devops`) en el host que posee el checkout | Sin la CLI o sin autenticación: `provider_unavailable` con la acción concreta; el desktop sigue funcionando con su implementación Dart |
| Protocolos terminal-host y mobile | Sin cambios de versión estricta | — |

## 8. Fases, PRs y estimaciones (orientativas)

PRs apilados hacia `main`, un commit por PR y títulos en minúsculas con Conventional Commits. Las estimaciones son días-persona de un ingeniero con contexto del repo.

| Fase | PR | Contenido | Est. |
|---|---|---|---|
| **0. Fundaciones** | 0a `refactor: split mcp tool catalog by domain` | Catálogo por dominio, `ToolSpec` v2 (idempotent, structured, outputSchema), executor con `structuredContent`, modelo de errores y `ALERA_MCP_ORIGIN` | 2 |
| | 0b `feat: add admin mcp access level to the runtime` | `McpAccess::Admin`, `ToolAccess::Admin`, relay y auth, CLI `--access`, `mcp serve --access` (11.R1), desktop MCP Control y tests | 2 |
| | 0c `feat: add mcp:admin scope to cloud oauth` | Migración 0024, consentimiento, gateway y contratos | 2 |
| | 0d `feat: accept admin tools and catalog v2 at the edge` | Edge: scopes, validador, relay y tests | 1 |
| | 0e `feat: add mcp mutation receipts and exclusion tests` | `mcpMutationReceipts`, `catalog_exclusion_tests` y test de que cada `Invocation` la acepta el parser clap del CLI | 1.5 |
| **1. From Prompt** | 1a `feat: add persisted prompt workspace operations` | Tabla, RPC `workspace.promptStart.*`, fases, cancelación y reconciliación | 3 |
| | 1b `feat: infer project in workspace identity generation` | Identidad v2 con proyectos, `needsInput` y error `ai_assist_unavailable` como la UI | 1.5 |
| | 1c `feat: expose prompt workspace start in cli and mcp` | CLI `prompt-start`, 6 herramientas, fix de `workspace start` y corrección de `start_agent_workspace` | 2 |
| | 1d `feat: use the runtime prompt workspace service on desktop` | Migración desktop por capability | 2 |
| | 1e `feat: use the runtime prompt workspace service on mobile` | Migración mobile | 1.5 |
| **2. Workspaces** | 2a `feat: add workspace show, wake and list filters` | `workspace show`, `workspace.wake`, filtros, pin, archive, focus, rename y herramientas | 2 |
| | 2b `feat: expose sections, tags and relations over mcp` | Herramientas y `--tree` | 1.5 |
| | 2c `feat: remove workspaces with ui semantics` | Buffer save (`checkoutBuffersSaveRequested` en desktop y mobile), `--editor-buffers`, preview, reenvío de `storageImpact` remoto, `remove_workspace` y `remove_project` | 3.5 |
| | 2d `feat: expose hand-off, recovery and setup over mcp` | Hand Off, recovery, setup, register y unregister | 1.5 |
| **3. Proyectos** | 3a `feat: add project rename, clone and branches commands` | CLI y herramientas de clone, rename, branches y hosts | 2 |
| | 3b `feat: expose project config over cli and mcp` | `project config` | 1.5 |
| **4. Tabs, terminales y perfiles** | 4a `feat: add tab rename, title and terminal lifecycle commands` | Rename, título, restart, terminate, pulse y prune | 2 |
| | 4b `feat: expose agent profiles over mcp with admin-only changes` | Lectura y lanzamiento de perfiles en Full (con reanudación de sesión); CRUD, reorden y perfil por defecto en Admin (F2) | 1.5 |
| | 4c `feat: expose runtime settings, quotas and resources over mcp` | Ajustes con allowlist, integraciones, cuotas, recursos y voz | 2 |
| **5. Inbox y orquestación** | 5a `feat: attribute shared inbox questions to mcp clients` | Origen, filtros, `wait_for_inbox`, cancel, read, conversations, purge, banner y UI del inbox | 2.5 |
| | 5b `feat: expose orchestration administration over mcp` | Tareas, dispatch, coordinador, board, gates (lista y creación), run policy (propuesta y vista), recover, transfer y reset | 2.5 |
| | 5c `feat: expose workflow proposals, plans and cleanup over mcp` | CLI nuevo para `workflows.*` (sin decisiones) y herramientas | 3 |
| **6. Automations** | 6a `feat: expose automation lifecycle over mcp` | CRUD, filtros, run-now completo, runs, take-over, plantillas y export/import | 3 |
| **7. Pull requests (multi-forja, F3)** | 7a `refactor: add a forge provider abstraction to runtime pull requests` | Trait `ForgeProvider`, GitHub movido detrás, fixtures compartidas exportadas desde las pruebas Dart y tests de regresión de GitHub | 3 |
| | 7b `feat: support gitlab merge requests in the runtime` | `GitLabProvider` (`glab`), portado de `gitlab_*` Dart: snapshot, pipelines, comentarios, create, merge, draft, close, summaries | 4 |
| | 7c `feat: support azure devops pull requests in the runtime` | `AzureDevOpsProvider` (`az repos pr`, policies y builds), portado de `azure_devops_*` Dart | 4 |
| | 7d `feat: add pr cli and mcp tools over runtime forge providers` | `alera pr` (show, summaries, create, details, link, comment, draft, close, merge, ship) y herramientas, con las tres forjas | 3 |
| | 7e `feat: dispatch restack and failed checks from the runtime` | Prompts únicos en Rust, RPC, CLI, herramientas y adopción desktop y mobile | 2 |
| | 7f `feat: run watch and fix and ship follow-up for every forge` | Evaluación y merge del watch vía `ForgeProvider`, `pullRequestWatchExecutionV2`, desktop sin doble vigilancia y ship con seguimiento | 3 |
| | 7g `feat: port pull request stacks to the runtime` | `pullRequestStack.*` (solo GitHub), CLI, herramientas y adopción desktop | 3 |
| **8. Eventos** | 8.0 (spike, sin código de producto) verificación de requisitos de MCP Events con la integración conectada | Acta con plan o workspace, controles, si la conexión es plugin, versión y métodos observados, scopes y pasos de configuración | 1 |
| | 8a `feat: add runtime event journal and polling tools` | `runtimeEvents`, escritura en todas las transiciones, `events list/wait`, herramientas y test de payloads | 3 |
| | 8b `feat: add resource subscriptions to mcp serve` | Modo listen del cliente host, resources, subscribe, progress y `subscriptions/listen` | 3 |
| | 8c `feat: forward runtime domain events to the cloud` | Reenviador persistente y endpoint con `events:send` (migración 0025, parte 1) | 2.5 |
| | 8d `feat: deliver signed webhooks for runtime events` | Tablas, worker, firma, SSRF, CLI, UI desktop y herramientas admin | 4 |
| | 8e `feat: support mcp events at the edge behind a flag` | `2026-07-28` en el edge, `server/discover` y `events/*`, ligado al grant | 3 |
| | 8f (prueba obligatoria) E2E real de MCP Events con la integración de Alera conectada en ChatGPT | Guion 6.5.5, criterio go/no-go y acta con evidencia; el polling se valida como fallback | 1.5 |
| **9. Cierre** | 9a `docs: document mcp parity and update agent skills` | `docs/remote-mcp.md`, `docs/mcp-capability-gap-audit.md`, skills `alera-cli` y `alera-orchestration`, `AGENTS.md` (eventos, admin) | 1.5 |
| | 9b Aceptación E2E completa | Matriz 9.4 en Linux, macOS y Windows | 2 |

**Total orientativo**: unos **90 días-persona**. Por fases: 0 = 8.5, 1 = 10, 2 = 8.5, 3 = 3.5, 4 = 5.5, 5 = 8, 6 = 3, 7 = 22, 8 = 18, 9 = 3.5. Con dos o tres personas en pistas paralelas, del orden de 7 a 10 semanas de calendario.

**Dependencias**:

- 0 antes que todo; 0a antes que 0b-0e.
- 1a → 1b → 1c → 1d y 1e.
- 2c necesita el buffer save en GUI.
- 5a necesita 0a (origen).
- 7a → (7b ∥ 7c) → 7d → 7f; 7e y 7g solo dependen de 7a.
- 8.0 se adelanta al inicio del proyecto: sus hallazgos pueden cambiar el alcance de 8e.
- 8a → 8b; 8a → 8c → 8d → 8e → 8f. La 8f necesita además 5a (atribución) para la prueba con `ask_agent`.

**Pistas paralelas posibles** tras la fase 0: (1), (2+3), (4+6), (5), (7a-7d), (7e-7g) y (8a-8b). La 8.0 puede hacerse en paralelo a la fase 0.

## 9. Pruebas

### 9.1 Unitarias y de contrato

- **Runtime** (`cargo test -p alera-cli`):
  - Catálogo: schemas válidos, la exclusión, cada `Invocation` aceptada por `clap` (`Cli::try_parse_from`), anotaciones y niveles.
  - Executor: `structuredContent`, errores y origen.
  - `relay_mcp_tests` con admin.
  - `mcp_settings` con cuatro niveles.
  - Algoritmo From Prompt con AI Assist falso (comando personalizado de AI Assist con respuestas fijas): proyecto único, inferido, ambiguo (`needsInput`), colisión con reintento y sufijo, "Others", fallo de lanzamiento y `retryLaunch`, cancelación y reinicio del host (reconciliación), idempotencia por `requestId`.
  - Payloads de eventos frente a la lista blanca.
  - `mcpMutationReceipts`.
- **alera-core**: esquemas nuevos, retención de `runtimeEvents` y migración idempotente.
- **Nube** (`cargo test`, con `TEST_DATABASE_URL` y `--include-ignored`): scope admin no concedido por defecto, el consentimiento lo marca explícitamente, el gateway lo exige, el CHECK de la migración, ingesta idempotente de domain events, worker de webhooks (reintentos, 410, 413, lease), SSRF y firma.
- **Edge** (`bun run check`, `bun test`): admin, catálogo v2, `server/discover`, `events/*` con la flag apagada y encendida, y ligadura al grant.
- **Desktop y mobile** (`flutter test`): MCP Control de cuatro niveles, migración From Prompt por capability (con y sin servicio), buffer save, origen en el inbox y dispatch de PR.

Notas de entorno:

- En `cargo test`, desactivar las `ALERA_*` heredadas con un bucle `unset`; en zsh, `env $LISTA` no separa palabras.
- Ejecutar `dart run tool/quality/check_max_lines.dart` (incluye `--packages` de mobile) antes de cada push.
- Inicializar `third_party/xterm` en worktrees para mobile.

### 9.2 Integración del runtime

Se amplía el harness `rust/alera-cli/tests/terminal_host_headless_runtime.rs` con casos MCP:

- `mcp serve` sobre un runtime aislado (`ALERA_RUNTIME_DIR` temporal) y un repo Git de fixture
- llamadas `tools/call` reales para cada dominio
- `resources/subscribe` recibiendo `notifications/resources/updated` al responder un agente simulado

### 9.3 E2E remoto

Se amplía `edge/tool/relay_integration.mjs` (Miniflare) con la ruta MCP (hoy usa `mcp: None`). En local van nube, edge (`wrangler dev --local`) y runtime con `alera account login --device`; se prueban OAuth (consentimiento con y sin admin), llamadas Read, Full y Admin, rechazo por scope o nivel, eventos reenviados y webhook a un receptor local (HTTPS con certificado de prueba).

### 9.4 Aceptación manual en máquina real

Script `tool/ci/mcp_parity_acceptance.py` (patrón de `tool/ci/*_acceptance.py`):

- usa el SDK MCP de Python como cliente stdio
- recorre la matriz 2.1 por dominio sobre un runtime aislado sin tocar la configuración del usuario
- guarda la evidencia (JSON de cada llamada)

Comprobaciones manuales:

1. From Prompt por MCP frente a la UI con el mismo prompt: misma sección o "Others", setup visible en desktop y mobile, agente activo.
2. Borrado con buffers sucios en desktop (Save y Discard) y con cambios git (se pierden, como la UI), con rama borrable y no borrable.
3. PR en repos de prueba de **GitHub, GitLab y Azure DevOps**: create, comment, draft o ready, ship con seguimiento, restack, fix checks, watch (`fix` y `fixAndMerge`) y merge con cada método de la forja. Stacks solo en GitHub. Todo con un grant **Full**.
4. Inbox compartido con dos clientes (ChatGPT y Claude o stdio): atribución, `own` y `all`, y que nadie reacciona a respuestas ajenas.
5. ChatGPT, con la integración ya conectada: acta 8.0, polling con cursor y prueba real de MCP Events (8f) con su criterio go/no-go.
7. Permisos: con un grant Full, borrar workspace o proyecto, merge y `purge_automations` funcionan; crear, editar o borrar perfiles y `set_default_agent_profile` devuelven `scope_required` o `access_denied`; con Admin funcionan.
6. Windows y macOS: From Prompt, borrado y eventos stdio (con los skills `build-on-windows` y `build-on-macos`).

### 9.5 Criterios de aceptación por fase

| Fase | Criterio verificable |
|---|---|
| 0 | Los grants existentes no ven herramientas Admin; un grant nuevo con admin y el runtime en admin ejecuta una herramienta Admin de prueba; con runtime en `full` devuelve `runtime_read_only` o `access_denied`; el test de exclusiones pasa; todas las herramientas devuelven `structuredContent` válido |
| 1 | El mismo prompt da nombre, rama y sección equivalentes por UI y por MCP; ambigüedad → `needsInput` con candidatos; un reintento con la misma `clientRequestId` no duplica; tras reiniciar el host, la operación queda `failed` y `retryLaunch` funciona; ninguna llamada pasa de 50 s |
| 2 | Con un grant **Full**, `remove_workspace` replica los resultados de la UI en los 6 casos (rama borrable o no, buffers save o discard, dependencias, bloqueo de almacenamiento, archivado, remoto); secciones y tags cuadran con la UI en vivo |
| 4 | Con Full, `list_agent_profiles`, `show_agent_profile` y `launch_agent` funcionan, y toda mutación de perfiles (incluidas reduced protections y el perfil por defecto) devuelve `scope_required` o `access_denied`; con Admin funciona |
| 3, 6 | Cada fila de la matriz tiene una prueba E2E verde en el script de aceptación; las automations se crean activas con Full |
| 5 | Dos clientes ven el historial compartido con `isOwn` correcto; el agente ve el nombre del cliente en el banner; ninguna herramienta de decisión humana está en el catálogo |
| 7 | En repos de prueba de GitHub, GitLab y Azure DevOps se completa desde MCP, con un grant Full, el flujo create → comment → draft/ready → ship con seguimiento → watch → fix → merge. Las fixtures compartidas pasan en Dart y Rust. Los stacks funcionan en GitHub y devuelven `provider_unsupported` en las otras forjas. El desktop no vigila dos veces |
| 8 | `wait_for_events` recibe `inbox.reply` en menos de 2 s tras la respuesta; stdio recibe `resources/updated`; el webhook llega firmado y verificable con reintentos probados; sin suscripciones no se reenvía nada a la nube (C1); acta 8.0 completa; 8f ejecutada con la integración conectada y resultado go (3 de 3 continuaciones en menos de 2 min) o no-go documentado con el polling validado |
| 9 | La documentación refleja solo el comportamiento implementado; la matriz se cumple al 100% en Linux, macOS y Windows |

## 10. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Unas 150 herramientas superan los límites prácticos de algunos clientes (descubrimiento, contexto del modelo) | Herramientas ignoradas o mal elegidas | Descripciones concisas; agrupar en el catálogo por dominio. Opcional: "toolsets" activables en MCP Control (aditivo, sin bloquear) |
| La inferencia de proyecto con IA falla o es inconsistente | Workspaces en el proyecto equivocado | Validación estricta contra la lista; `needsInput` ante la duda; nunca elegir en silencio |
| Buffer save entre clientes (desktop o mobile desconectados) | Borrado bloqueado | Error `blocked` claro con alternativa `editorBuffers: discard`; el default `save` nunca pierde datos en silencio |
| Pérdida de cambios git sin commitear al borrar (semántica de la UI, disponible con Full por F1) | Pérdida de datos | Advertencia literal de la UI en la descripción de la herramienta y en el resultado (`uncommittedChangesLost`) |
| Multi-forja (F3): `glab` y `az` en el host del checkout, diferencias semánticas entre forjas (métodos de merge, drafts, checks) y dos implementaciones (Dart y Rust) | Errores en hosts sin CLI y deriva | `provider_unavailable` con acción concreta; mapeo explícito por forja; fixtures compartidas Dart y Rust; repos de prueba en las tres forjas |
| Credenciales de prueba para GitLab y Azure DevOps | Bloquea la aceptación de 7b y 7c | Preparar proyectos de prueba y tokens antes de la fase 7 |
| MCP Events: la conexión actual puede no contar como plugin, el plan o workspace de ChatGPT puede no tener Work chats o tareas activadas por eventos, y la continuación no está demostrada (EducUp) | Prueba 8f imposible o no-go | 8.0 lo verifica antes de invertir en 8e; los bloqueos externos se informan; el polling y los webhooks siguen siendo el camino garantizado |
| Desfase entre el catálogo del edge y los runtimes | Errores `tool_unavailable` | Mensaje con la versión mínima; orden de despliegue (sección 7) |
| Fiabilidad de reenvío de eventos (hoy el push vive solo en memoria) | Eventos perdidos | Diario persistente con `forwardedAt` y reintentos; ingesta idempotente |
| Fuga de contenido por PR o comentarios a la nube y al proveedor | Privacidad | Aceptado por U6; solo en Full; los eventos sin contenido |
| Bug actual: `storageImpact` no se reenvía a hosts remotos | Borrado remoto bloqueado en desktop | Se corrige en 2c, con test |
| Bug actual: mobile llama a `workspace.runSetup` sin estar en la allowlist | Recovery falla en el teléfono | Corregir en 2d (añadir a `mobile_request_allowed`) |
| Carga de mantenimiento (CLI, catálogo, edge, GUI) | Deriva | Test catálogo↔edge (existe), test catálogo↔clap y test de exclusiones |

## 11. Supuestos y decisiones residuales (no bloqueantes)

| # | Default adoptado | Alternativa | ¿Bloquea? |
|---|---|---|---|
| R1 | **`mcp serve` local**: conserva el comportamiento actual (Full aunque MCP Control esté en Off, porque es confianza local de un usuario con shell). Se añade `--access read|full|admin`; Admin solo con `--access admin` explícito; `--read-only` queda como alias. MCP Control indica "aplica a clientes remotos" | Respetar el nivel del runtime en local (rompería configuraciones locales existentes cuando está en Off) | No |
| R2 | Resuelta por F1 y F2 (sección 3.2) | — | — |
| R3 | `cancel_task` se queda en Full por compatibilidad | Moverla a Admin (rompe grants) | No |
| R4 | `wait_for_inbox` usa `own` por defecto; `list_inbox_threads` usa `all` | Ambos en `all` | No |
| R5 | `mode: auto` = worktree en repos Git; la UI envía su modo explícito | `auto` = carpeta del proyecto, como la UI | No |
| R6 | Webhooks gestionables por MCP solo con Admin, y desde la UI y el CLI | Solo desde la UI | No |
| R7 | Resuelta por F3: multi-forja obligatoria (fase 7) | — | — |
| R8 | El prompt de From Prompt se conserva hasta completar y luego solo su hash | Conservarlo para auditoría | No |
| R9 | Resuelta (C3): sin AI Assist, mismo error que la UI | — | — |
| R10 | `purge_inbox` queda en Admin porque borra el historial compartido de todos los clientes (no lo nombra F1) | Moverlo a Full | No |
| R11 | Stacks solo en GitHub, igual que el desktop (GitLab y Azure DevOps no tienen equivalente en Alera) | Diseñar stacks para otras forjas (fuera de la paridad) | No |
| R12 | El desktop conserva su implementación Dart de PR; la adopción del runtime solo es obligatoria para watch (evitar doble dispatch) y agent dispatch | Migrar todo el desktop al runtime | No |

No hay preguntas bloqueantes.

## 12. Fuentes

- Auditoría: [mcp-capability-gap-audit.md](mcp-capability-gap-audit.md), secciones 4, 6 y 11.
- Código citado con rutas y líneas a partir de `c8b3d3984`.
- Referencia de eventos: `~/Projects/educup/educup-automations/docs/mcp-events.md`.
- Externas: [OpenAI MCP Events](https://developers.openai.com/plugins/build/mcp-events) y [MCP 2026-07-28](https://blog.modelcontextprotocol.io/posts/2026-07-28/).

## 13. Estado de implementación (rama `feat/mcp-parity`)

Implementado y verificado:

- **Catálogo:** 220 herramientas (86 Read, 112 Full, 22 Admin). Los tests de catálogo verifican tres cosas: que cada invocación la acepta el parser real del CLI, que ninguna herramienta llega a un comando excluido ni a una decisión humana, y que los niveles siguen F1 y F2.
- **Fases 0-6, 7 y 8:** implementadas tal como describe este plan.
- **Validación:**
  - Rust `alera-cli`: 2036 tests en verde; `alera-core` con la feature `runtime` también en verde.
  - Cloud: 86 tests unitarios y 13 contratos con Postgres.
  - Edge: 106 tests.
  - Flutter: 4505 tests en desktop y 937 en mobile.
  - `flutter analyze`, clippy, fmt, el ratchet de líneas y la consistencia de codegen sin incidencias.
- **Aceptación de extremo a extremo** con `tool/ci/mcp_parity_acceptance.py`: 10 de 10 escenarios. Se ejecuta con un cliente MCP real (`alera mcp serve`) sobre un runtime aislado y cubre:
  - New Workspace from Prompt: inferencia, sección y "Others", idempotencia, candidatos, modo carpeta del proyecto y colisiones;
  - el diario de eventos;
  - las suscripciones a recursos.

Diferencias con el plan:

- **Idempotencia:** no se creó la tabla genérica `mcpMutationReceipts`. Usan las claves nativas existentes (`--client-mutation-id`, `--request-key`, `requestId`) donde las hay.
- **Ship:** sigue siendo síncrono y puede superar los 58 s del cliente. El ship continúa en el runtime y se consulta luego con `get_pull_request`.
- **Merge en Azure DevOps:** solo `mergeCommit` y `squash`, como en el desktop.
- **Stacks:** el desktop sigue usando su implementación Dart de stacks.

Pendiente (requiere despliegue, cuentas reales o pruebas manuales):

- **MCP Events (8.0 y 8f):** la verificación de requisitos y la prueba real en ChatGPT necesitan desplegar edge y nube, con estos ajustes:
  - `ALERA_WEBHOOK_SECRET_KEY`;
  - `MCP_EVENTS_ENABLED` / `ALERA_MCP_EVENTS_ENABLED`;
  - `EVENT_DELIVERY_PUMP=true`, o `cpu_idle = false` en Cloud Run.
- **PR en forjas reales:** pruebas de extremo a extremo con cuentas y repos reales de GitLab y Azure DevOps (`glab`, `az`).
- **Pruebas manuales en máquina real:**
  - borrado con buffers sucios (save y discard);
  - wake;
  - Setup lanzado por el host;
  - inbox compartido entre dos clientes;
  - Windows y macOS.

### 13.1 Revisión de seguridad

Corregido en el runtime:

- **Buffers sucios:** solo un cliente local puede pedir `save` o `discard` de editores, y solo al borrar un workspace. Un teléfono o un satélite no pueden resolver los editores de otro cliente.
- **Satélites:** el hub rechaza `workspace.promptStart.*` (start, retryLaunch, cancel) y `workspace.wake` de un host remoto. Además, quita `externalOrigin`, `origin` y `resolution` de todo payload reenviado.
- **Origen de New Workspace from Prompt:** la conexión decide la superficie (desktop, mobile, cli). Solo el CLI local que ejecuta una herramienta MCP puede nombrar al cliente MCP. El origen se normaliza con las mismas cotas que el buzón.
- **`requestId` de New Workspace from Prompt:** limitado a 128 caracteres y separado por cliente MCP. Dos clientes que elijan la misma clave nunca comparten operación.
- **`ALERA_MCP_ORIGIN`:** no pasa a un runtime arrancado por una llamada ni a sus terminales.
- **`list_webhooks`:** pasa a Admin, porque la URL de callback suele llevar el token del receptor.
- **Borrado bloqueado:** si un borrado se bloquea por editores, el mensaje ya no dice que no cambió nada cuando las automations dependientes ya se pausaron y sus ejecuciones se cancelaron.
- **Test de exclusiones:** ahora recorre todas las variantes de argumentos de cada herramienta y toda la ruta de subcomandos.

Corregido en las forjas de PR:

- **Inyección en Windows:** `glab` y `az` ya no pasan texto libre por la línea de comandos.
  - GitLab crea, comenta y edita con `glab api --input -` y el cuerpo JSON por stdin.
  - Azure crea con `az devops invoke --in-file`.
  - En Windows el runner local lanza la CLI directamente, resolviéndola con `PATH` y `PATHEXT`, sin pasar por `cmd.exe`. Nunca busca la CLI en el checkout.
- **Expansión `@file` de `az`:** se rechaza cualquier argumento que empiece por `@`. Una rama así se pasa como `refs/heads/@…`.
- **Carrera al mezclar en Azure:** el merge envía `lastMergeSourceCommit` con la cabeza esperada para que Azure rechace una cabeza vieja. Con un checkout local el cuerpo va en un archivo. En un host SSH va por stdin (`--in-file /dev/stdin`); en un host Windows, que no tiene esa ruta, el merge se rechaza en vez de hacerse sin la guarda.
- **Setup en reintentos:** el id de la pestaña Setup se guarda antes de crearla, así que el setup corre como mucho una vez. Si no se puede confirmar, queda el comando con un aviso para que el usuario decida.
- **Archivo temporal de Azure:** se crea nuevo y solo para el dueño (0600), y se borra al terminar la llamada.

Corregido en los eventos de la nube:

- **MCP Events respetan MCP Control:** con el runtime en Off no hay fan-out ni replay, la entrega en cola se detiene con `runtime_mcp_disabled` y una suscripción nueva recibe `409`. Los webhooks no dependen de MCP Control.
- **Bomba de entregas:** `/v1/internal/*` exige siempre el token de origen.
- **Un evento rechazado ya no bloquea el reenvío:** la nube guarda el resto del lote y lista los rechazados en `rejected`.
- **Eventos al crear una suscripción:** el forwarder refresca el conteo al crear un webhook. Mientras el conteo es cero, solo descarta eventos anteriores al último refresco.

Decisión abierta (M6), sin cambios de nivel hasta que el usuario decida:

- **El problema:** Full ya permite ejecutar comandos arbitrarios en la máquina del runtime por varias vías:
  - `create_tab` con `command`;
  - la entrada de `pulse`;
  - `write_terminal`;
  - la configuración del proyecto (setup) seguida de `run_workspace_setup`;
  - el `precheck.command` de una automation.
- **La consecuencia:** un cliente Full puede llegar por esas vías a cualquier comando del CLI, incluidos los excluidos (`orchestration gate-resolve`, `mcp`, `account`). La exclusión del catálogo impide que una herramienta los invoque directamente, pero no es una barrera frente a un cliente Full decidido.
- **Opciones:**
  - aceptarlo y documentarlo en la UI de MCP Control como hoy (`write_terminal`);
  - subir a Admin las herramientas que aceptan comandos libres (`create_tab.command`, la configuración de setup y `precheck.command`), sin tocar `write_terminal` ni `pulse`, que son el uso principal de Full;
  - restringir los comandos libres a una lista blanca por proyecto.
