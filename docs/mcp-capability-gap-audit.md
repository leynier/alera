# Auditoría de brechas: GUI y CLI de Alera frente a su MCP

Fecha: 2026-10-10. Base: `c8b3d3984` (release v0.104.1). Alcance: código fuente real de la GUI desktop (`lib/`), la app mobile (`mobile/lib`), el CLI (`rust/alera-cli`), el runtime host (`rust/alera-cli/src/terminal_host`) y el edge (`edge/src/mcp`). Solo investigación: no se implementó ni se modificó código.

## 1. Resumen ejecutivo

- El MCP de Alera expone **31 herramientas** (21 de lectura, incluidas 3 esperas acotadas, y 10 de ejecución), más `list_runtimes`, que solo existe en el edge. El CLI tiene unos **200 subcomandos** y el runtime host atiende **más de 400 métodos RPC**. La cobertura del MCP es intencionalmente estrecha: se centra en descubrir, lanzar agentes, conversar con ellos y orquestar.
- Cada herramienta MCP es una sola invocación `alera <grupo> --json <acción>` en un proceso hijo (`rust/alera-cli/src/mcp_tools/executor.rs:69`). Exponer un comando CLI existente cuesta poco: hace falta una entrada de catálogo y regenerar `edge/src/mcp/tool_catalog.json`. Lo que solo existe en la GUI (git, PRs, archivos, búsqueda, config de proyecto, workflows) necesita antes un comando CLI o una vía RPC nueva.
- Brechas más valiosas: gestión de secciones, tags y relaciones de workspaces, renombrar, archivar o eliminar workspaces, issue enlazado, Watch and Fix, detalle y control de automations, cancelar preguntas del inbox, ramas del proyecto y lectura del estado de git y PR.
- Hallazgo principal sobre **New Workspace from Prompt**: la orquestación está implementada **tres veces**, en Dart desktop, Dart mobile y Rust del CLI. Solo la generación de identidad (nombre, rama y sección con fallback "Others") es un servicio backend reutilizable. `start_agent_workspace` diverge de la UI en seis puntos (sección automática, colisiones, rama origen por defecto, setup diferido, idempotencia y timeout). Además, **ningún flujo infiere el proyecto desde el prompt**. Detalle en la sección 6.
- Riesgos destacados: posible workspace a medio crear cuando `start_agent_workspace` agota el timeout del MCP mientras genera la identidad o corre el setup en línea, falta de clave de idempotencia en los lanzamientos vía MCP, `write_terminal` equivale a ejecución arbitraria, y `alera mcp serve` local ignora el nivel de acceso configurado en MCP Control.
- Comunicación bidireccional (sección 11): el servidor MCP solo admite tools, en request/response sin estado. No hay notificaciones, recursos, SSE, sesiones ni elicitation, así que hoy la única vía es el polling acotado de `wait_*`. Ningún mecanismo estándar de MCP despierta a ChatGPT: lo único que lo consigue son las MCP Events de OpenAI (webhooks firmados, no estándar). EducUp las implementó, pero la continuación real en ChatGPT sigue sin demostrarse.

## 2. Superficie MCP actual

Catálogo: `rust/alera-cli/src/mcp_tools/catalog_read.rs` y `catalog_execute.rs`. Copia generada para el edge: `edge/src/mcp/tool_catalog.json` (sincronizada: 31 = 31).

| Herramienta MCP | Acceso | Invocación CLI |
|---|---|---|
| `runtime_status` | read | `runtime status` |
| `list_projects` | read | `project list` |
| `list_workspaces` | read | `workspace list [--project-id] [--host-id] [--all]` |
| `list_tabs` | read | `tab list --workspace-id` |
| `list_agent_profiles` | read | `agent-profile list` |
| `list_terminals` / `show_terminal` / `read_terminal` | read | `terminal list/show/read` |
| `wait_for_terminal` | read | `terminal wait` (≤50 s) |
| `list_tasks` / `show_task` / `wait_for_task` | read | `orchestration task-list/task-show/task-wait` |
| `list_runs` / `orchestration_status` / `list_messages` | read | `orchestration run-list/status/inbox` |
| `list_inbox_targets` / `list_inbox_threads` / `show_inbox_thread` / `wait_for_reply` | read | `inbox targets/threads/show/wait` con `--inbox ext:mcp` |
| `list_automations` / `list_automation_runs` | read | `automation list/runs` |
| `create_workspace` | execute | `workspace add` |
| `start_agent_workspace` | execute | `workspace start --prompt-stdin --no-parent` |
| `launch_agent` | execute | `agent-profile launch --prompt-stdin` |
| `delegate_task` | execute | `orchestration delegate --spec-stdin --keep-on-failure` |
| `write_terminal` | execute | `terminal write --stdin [--submit/--enter]` |
| `send_message` | execute | `orchestration send` |
| `ask_agent` | execute | `inbox ask --inbox ext:mcp` |
| `cancel_task` | execute (destructive) | `orchestration task-cancel --force` |
| `sleep_workspace` | execute (destructive) | `workspace sleep` |
| `run_automation` | execute | `automation run-now` |

Control de acceso:

- **Remoto** (edge y relay): el token necesita el scope `mcp:execute` para las herramientas de ejecución (`edge/src/mcp/tool_call.ts:190`). El runtime vuelve a comprobar el grant y `settings.mcp.access` (off, read o full) en `terminal_host/relay_mcp.rs:218-234`.
- **Local** (`alera mcp serve`): solo filtra con `--read-only` (`mcp_commands.rs:52`, `mcp_tools/stdio_server.rs:144`). No consulta `settings.mcp.access`. Ver riesgo R3.

## 3. Leyenda

- **Cubierta**: el MCP ofrece la acción con semántica equivalente.
- **Parcial**: el MCP la ofrece, pero faltan opciones o la semántica difiere de la GUI o el CLI.
- **Brecha**: no hay equivalente MCP.
- **Por diseño**: no debería exponerse, o solo con salvaguardas (seguridad, decisiones humanas, gestión del propio acceso).
- Prioridad: **P1** alto valor para agentes y clientes MCP con riesgo bajo; **P2** valor medio, o alto valor con salvaguardas; **P3** valor bajo o nicho; **—** no exponer.
- Columna GUI: D = desktop, M = mobile. Columna CLI: comando o "—".

## 4. Matriz de brechas

### 4.1 Runtime y host

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Estado del runtime | D (panel runtime host) | `runtime status` | `runtime_status` | Cubierta | — |
| Versiones y contratos (CLI, host, skills) | — | `version` | — | Brecha. Permite que un cliente detecte incompatibilidades antes de llamar | P2 |
| Iniciar, detener o reiniciar el runtime | D, M (`host.restart`) | `runtime start/stop` | — | Por diseño: detenerlo corta la propia sesión MCP | — |
| Borrar el estado del runtime | — | `runtime clear` | — | Por diseño: destructivo | — |
| Integraciones de agentes (hooks) | D (Settings › Agents) | `runtime agents status/enable/disable` | — | Brecha. Solo `status` tiene sentido exponer | P3 |
| Nombre del runtime | D (MCP Control) | `runtime rename` | — | Brecha | P3 |
| Snapshot de recursos (CPU y memoria) y matar sesiones | D (status bar) | — | — | Brecha, solo GUI (`resources.snapshot`). Útil para diagnosticar agentes colgados | P2 (lectura) |
| Cuotas de agentes | D, M | — | — | Brecha, solo GUI (`agentQuota.snapshot`). Ayuda a elegir perfil antes de lanzar | P2 |

### 4.2 Proyectos

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Listar proyectos | D, M | `project list` | `list_projects` | Cubierta | — |
| Registrar proyecto local | D, M | `project add` | — | Brecha | P2 |
| Clonar proyecto desde URL | D, M (`project.clone.*`) | Solo `project add-remote` (SSH) | — | Brecha. El clon local solo existe en la GUI | P2 |
| Registrar proyecto remoto o checkout SSH | D | `project add-remote`, `project register-checkout` | — | Brecha | P3 |
| Renombrar proyecto | D, M (`project.rename`) | — | — | Brecha, solo GUI | P3 |
| Eliminar proyecto | D, M | `project remove` | — | Por diseño (destructivo), o como mucho con confirmación explícita | — |
| Hosts del proyecto | D | `project hosts list/add/remove` | — | Brecha. `list` es lectura útil | P2 (list) / P3 |
| Ramas del proyecto (catálogo) | D, M (`project.branches.list`) | — | — | Brecha, solo GUI. Hoy un cliente MCP no puede saber qué `sourceBranch` pasar | **P1** |
| Configuración efectiva del proyecto (New Workspace, setup, copy rules) | D, M (`projectConfig.*`) | — | — | Brecha, solo GUI. Leerla da la rama origen preferida | P2 (lectura) / P3 (escritura) |

### 4.3 Workspaces

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Listar workspaces | D, M | `workspace list` | `list_workspaces` | Parcial: filtra solo por proyecto y host; sin filtros de sección, tag o archivado (el campo `isArchived` sí viene) | P3 |
| Crear workspace | D, M | `workspace add` | `create_workspace` | Parcial: no expone `sectionId`, `parentWorkspaceId`, `reuseExistingBranch`, `path`, `workspaceRoot` ni `id`; la sección solo va por nombre | P2 |
| Crear desde prompt y lanzar agente | D, M | `workspace start` | `start_agent_workspace` | Parcial con divergencias graves; ver sección 6 | **P1** |
| Renombrar | D, M | `workspace rename` | — | Brecha | **P1** |
| Asignar, quitar, crear o borrar sección; listar secciones | D, M | `workspace section list/set/clear/create/remove` | — | Brecha (solo `section` por nombre al crear) | **P1** (list/set/clear) / P2 (create/remove) |
| Tags: asignar, quitar, listar, crear, borrar | D, M | `workspace tag/untag`, `tag list/upsert/remove` | — | Brecha | P2 |
| Relación padre/hijo | D, M | `workspace link/unlink` | — | Brecha (`start_agent_workspace` fuerza `--no-parent`) | P2 |
| Fijar o desfijar en el sidebar | D, M | `workspace pin/unpin` | — | Brecha | P3 |
| Archivar o desarchivar | D, M | `workspace archive/unarchive` | — | Brecha | P2 |
| Dormir | D, M | `workspace sleep` | `sleep_workspace` | Cubierta | — |
| Despertar | D, M (implícito al abrir) | — (implícito) | — | Brecha: no hay verbo explícito; ni la GUI ni el CLI tienen uno | P3 |
| Eliminar workspace (y su worktree) | D, M | `workspace remove` | — | Brecha. Exponer solo con `destructiveHint`, preflight `removalDependencies` y sin `--delete-branch` por defecto | P2 |
| Hand Off / Hand On | D, M | `workspace hand-off/hand-on` | — | Brecha | P2 |
| Setup y recovery del worktree | D, M | `workspace setup`, `workspace recovery` | — | Brecha | P3 |
| Enfocar en la app desktop | — | `workspace focus` | — | Brecha (exige desktop abierto) | P3 |
| Registrar o desregistrar (reparación de metadatos) | — | `workspace register/unregister` | — | Por diseño: reparación de bajo nivel | — |
| Vista previa de cascada | — | `workspace cascade-preview` | — | Brecha | P3 |
| Issue enlazado: ver, enlazar, desenlazar | D, M | `workspace issue show/link/unlink` | Solo `issueUrl` al crear | Parcial | **P1** (show) / P2 (link/unlink) |
| Leer issue sin workspace | D | `issue show` | — | Brecha | P2 |
| Watch and Fix del PR | D, M | `workspace pr-watch show/start/stop` | — | Brecha | **P1** |
| Opciones de vista del sidebar | D, M (`workbenchViewPrefs.*`) | — | — | Por diseño: preferencia de UI | — |

### 4.4 Tabs, terminales y agentes

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Listar tabs | D, M | `tab list` | `list_tabs` | Cubierta (ver riesgo R5) | — |
| Crear tab de terminal o comando | D, M | `tab create [--command] [--spawn]` | — | Brecha (`write_terminal` exige que la terminal ya exista) | P2 |
| Cerrar tab o terminar terminal | D, M | `tab remove` | — | Brecha. Hoy un cliente MCP no puede cerrar un agente que lanzó | P2 |
| Renombrar tab | D, M (`tab.rename`) | — | — | Brecha, solo GUI | P3 |
| Reiniciar terminal | D, M (`terminal.restart`) | — | — | Brecha, solo GUI | P2 |
| Re-vincular agente a tab | — | `tab link-agent` | — | Brecha (pensado para ejecutarse dentro del agente) | P3 |
| Listar, ver, leer y esperar terminales | D, M | `terminal list/show/read/wait` | 4 herramientas | Cubierta | — |
| Escribir en terminal | D, M | `terminal write` | `write_terminal` | Parcial: sin `--file`. Ver riesgo R4 | — |
| Purgar sesiones detenidas | — | `terminal prune` | — | Brecha | P3 |
| Terminal Pulse | D | — | — | Brecha, solo GUI | P3 |
| Recuperar control desde mobile | D (`terminal.reclaim`) | — | — | Por diseño | — |
| Listar perfiles de agente | D, M | `agent-profile list` | `list_agent_profiles` | Cubierta | — |
| Ver un perfil | D | `agent-profile show` | — | Brecha (solo lectura) | P2 |
| Crear, actualizar, borrar o reordenar perfiles | D | `agent-profile create/update/remove/reorder/removal-impact` | — | Brecha. Un perfil define comandos ejecutables: tratarlo como ejecución privilegiada | P3 |
| Lanzar perfil en workspace existente | D, M | `agent-profile launch` | `launch_agent` | Parcial: sin `clientMutationId` (idempotencia), sin reanudar sesión (`resumeSessionId` existe en RPC y no en CLI) y sin adjuntos | P2 |
| Generar título de agente o tab | D, M (`aiText.agentTitle.generate`) | — | — | Brecha, solo GUI | P3 |

### 4.5 Orquestación y workflows

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Tareas: listar, ver, esperar | D (Run Board) | `orchestration task-list/task-show/task-wait` | 3 herramientas | Cubierta | — |
| Delegar tarea | — | `orchestration delegate` | `delegate_task` | Parcial: fuerza `--keep-on-failure` y no expone `parentWorkspaceId`, `workspaceRoot` ni `path` | P3 |
| Cancelar tarea | D | `orchestration task-cancel` | `cancel_task` | Cubierta, como cancelación administrativa con `--force` | — |
| Crear tarea sin agente; dispatch manual | — | `orchestration task-create/dispatch` | — | Brecha | P3 |
| Mensajes: enviar, listar | — | `orchestration send/inbox` | `send_message`, `list_messages` | Cubierta (`send` sin `--payload`, `--task-id` ni `--files-modified`) | — |
| check, reply, context, heartbeat, escalate, complete, worker-done | — | `orchestration …` | — | Por diseño: ciclo de vida del worker, necesita identidad de terminal | — |
| Decision gates: listar | D | `orchestration gate-list` | — | Brecha (lectura) | P2 |
| Decision gates: crear o resolver | D | `orchestration gate-create/gate-resolve` | — | Por diseño, o solo con confirmación humana explícita: son decisiones humanas | — |
| Run policy: proponer, ver, aprobar, rechazar | D | `orchestration run-policy-*` | — | `show` es brecha de lectura (P2); aprobar o rechazar es por diseño | P2 / — |
| Coordinador: iniciar, detener, ver run | D | `orchestration run/run-stop/run-show` | `list_runs`, `orchestration_status` | Parcial: faltan `run-show`, iniciar y detener | P2 |
| Recuperar tarea, transferir coordinador, reset | — | `orchestration task-recover/transfer-coordinator/reset` | — | Por diseño: administrativo o destructivo (`reset`) | — |
| Recetas: listar, ver, validar, guardar | D (Settings › Workflows) | `orchestration recipes …` | — | Brecha (lectura y validación) | P3 |
| Planes, propuestas, aprobación y revisión de workflows | D (`workflows.*`, firma con FRB) | Parcial: `orchestration plans …`, `orchestration workspaces …` | — | Por diseño en las decisiones (firmadas y "desktop-only" según la ayuda del CLI); la lectura es brecha P3 | P3 / — |
| Limpieza de recursos de workflows | D | — | — | Brecha, solo GUI | P3 |

### 4.6 Inbox

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Preguntar a un agente; destinos; hilos; esperar respuesta | D, M | `inbox ask/targets/threads/show/wait` | 5 herramientas | Cubierta, aislada en el inbox `ext:mcp` (no ve las preguntas del usuario) | — |
| Cancelar pregunta no entregada | D, M | `inbox cancel` | — | Brecha | **P1** |
| Marcar respuestas como leídas | D, M | `inbox read` | — | Brecha | P2 |
| Conversaciones entre agentes (lectura) | D, M | `inbox conversations/conversation` | — | Brecha | P2 |
| Listar inboxes; purgar | D, M | `inbox list/purge` | — | Brecha (`purge` destructivo) | P3 |

### 4.7 Automations

| Acción | GUI | CLI | MCP | Brecha | Prioridad |
|---|---|---|---|---|---|
| Listar automations | D, M | `automation list` | `list_automations` | Parcial: faltan los filtros `--include-trashed`, `--profile-id`, `--tag`, `--workspace-id`, `--section-id`, `--host-id` y `--bucket` | P3 |
| Ver automation (con runs y auditoría) | D, M | `automation show` | — | Brecha | **P1** |
| Listar runs | D, M | `automation runs` | `list_automation_runs` | Cubierta | — |
| Ver un run | D, M | `automation run-show` | — | Brecha | **P1** |
| Ejecutar ahora | D, M | `automation run-now` | `run_automation` | Parcial: sin `--skip-precheck`, `--overlap` (en cola o en paralelo) ni `--continue-from-run` | P2 |
| Cancelar run | D, M | `automation cancel` | — | Brecha | **P1** |
| Pausar o reanudar | D, M | `automation pause/resume` | — | Brecha | P2 |
| Crear o editar; readiness; vista previa de cron | D, M | `automation create/edit/readiness/preview-schedule` | — | Brecha (readiness y preview son lectura pura) | P2 |
| Papelera o restaurar; purgar | D, M | `automation trash/restore/purge` | — | Brecha; `purge` por diseño | P3 / — |
| Reanudar run en espera o extender plazo | D, M | `automation wait/extend` | — | Brecha | P2 |
| Tomar el control del terminal de un run | D, M (`automation.takeOver`) | — | — | Brecha, solo GUI | P3 |
| Plantillas, tags, importar o exportar catálogo | D, M | `automation templates/tags/import/export` | — | Brecha | P3 |
| context, heartbeat, complete | — | `automation context/heartbeat/complete` | — | Por diseño: ciclo de vida del agente dentro del run | — |

### 4.8 Capacidades solo GUI (sin CLI ni MCP)

Estas capacidades no tienen comando CLI. Exponerlas por MCP exige primero un comando CLI (por la arquitectura de `mcp_tools`, una invocación CLI por herramienta) o cambiar el ejecutor para llamar RPC directamente.

| Área | Acciones GUI (D, M) | RPC existente | Brecha MCP | Prioridad |
|---|---|---|---|---|
| Git (lectura) | Status, diff, historial, ramas, stashes | `git.*` (solo local), `mobile.git.status/diff/branches` | Brecha. Clave para clientes web (ChatGPT, Claude.ai) que no tienen shell | P2 |
| Git (escritura) | Stage, unstage, discard, commit, amend, fetch, pull, push, sync, stash, checkout, crear rama | `git.*`, `mobile.git.*` | Brecha. Preferible delegar a un agente; si se expone, separado y con `destructiveHint` en discard | P3 |
| Pull requests (lectura) | Snapshot, checks, conversación | `mobile.pullRequest.snapshot/summaries` | Brecha | P2 |
| Pull requests (escritura) | Crear, enlazar, comentar, merge, draft, cerrar, Ship, stacks, restack | `mobile.pullRequest.*`, `linkedReview.*` y CLI de forjas (`gh`, `glab`, `az`) | Brecha. Merge y Ship son de alto impacto | P3 |
| Archivos | Listar o leer, editar, crear, renombrar, mover, borrar | `mobile.workspaceExplorer.list`, `mobile.workspaceFile.read`, `workspace.files.*` | Brecha. Lectura útil; expone código fuente al cliente cloud | P2 (lectura) / P3 |
| Búsqueda y reemplazo; quick open | Buscar o reemplazar en archivos; Mod+P | `mobile.workspaceSearch.*`, `mobile.workspaceQuickOpen.*` | Brecha | P2 (buscar) / P3 (reemplazar) |
| Texto con IA | Mensaje de commit, detalles de PR, títulos | `aiText.*.generate` | Brecha | P3 |
| Comentarios para agentes | Comentar líneas y despachar a un agente | `write`, `agentProfile.launch` | Cubierta en esencia por `write_terminal` y `launch_agent` | — |
| Layout, splits, paneles, vista | Dividir, mover tabs, paneles de contexto | `layout.upsert`, `workbenchViewPrefs.*` | Por diseño: estado de UI | — |
| Settings | AI Assist, Terminal, Editor, Keyboard, Voice, Dictation, Text Actions | `configuration.settings.*`, `runtimeSettings.*` | Por diseño: preferencias del usuario | — |
| Configuration Sync | Revisar y aplicar sincronización en la nube | `configuration.cloud.*`, `configuration.transfer.*` | Por diseño | — |
| Updater, skills, registro del CLI | Actualizar app, instalar skills | `cliRegistration.*`, `agentSkill.install` | Por diseño | — |
| Reading Diff, dictado, text actions | — | FRB local | Por diseño / no aplica | — |

### 4.9 Seguridad, cuentas y conectividad (por diseño fuera del MCP)

| Acción | GUI | CLI | MCP | Comentario | Prioridad |
|---|---|---|---|---|---|
| SSH targets: listar o ver estado | D | `ssh-target list/status` | — | Brecha de lectura razonable | P2 |
| SSH targets: alta, baja, bootstrap, link | D | `ssh-target add/remove/bootstrap*/link` | — | Por diseño: credenciales e instalación remota | — |
| Mobile: habilitar, emparejar, dispositivos | D | `mobile …` | — | Por diseño: escalada de acceso | — |
| Cuenta Alera: login, logout, borrar, transferir | D | `account …` | — | Por diseño | — |
| MCP Control: habilitar, apps, revocar | D | `mcp status/enable/disable/apps/revoke` | — | Por diseño: un cliente MCP no debe gestionar su propio acceso. `mcp status` podría exponerse en solo lectura | — |
| Voz: hablar al humano | D, M | `voice speak` | — | Brecha útil para avisar al humano | P3 |
| Voz: estado o carpeta home | D, M | `voice status/ensure` | — | Brecha | P3 |

## 5. Capacidades parciales: detalle

1. `start_agent_workspace`. Ver la sección 6.
2. `create_workspace`: no permite padre, `reuseExistingBranch`, sección por id ni ruta. La GUI manual sí los ofrece (`lib/src/features/workbench/presentation/create_workspace_dialog_*.dart`).
3. `launch_agent`: el CLI acepta `--client-mutation-id` (`agent-profile launch`) y la GUI siempre usa `agentProfile.launchIdempotent`, pero el MCP no pasa ninguna clave. Un reintento del cliente tras un timeout puede lanzar dos agentes.
4. `delegate_task`: siempre `--keep-on-failure` y `--timeout-ms` ≤ 50 s. Como `delegate` espera a que el agente acepte, en perfiles lentos el MCP devuelve timeout aunque la tarea siga en curso.
5. `run_automation`: no expone las variantes de la GUI (sin precheck, en cola, en paralelo, continuar desde un run).
6. `list_inbox_threads`: siempre `--inbox ext:mcp`. Es intencional, pero un cliente MCP no puede consultar las preguntas que el usuario hizo desde la GUI.
7. `list_automations`: solo `state`, `projectId` y `search`.
8. `write_terminal`: sin `--file`. No es crítico, porque el texto ya viaja por stdin con un límite de 64 KiB.

## 6. New Workspace from Prompt: análisis y propuesta MCP

### 6.1 Cómo lo implementa la UI desktop

Puntos de entrada (los tres abren `showCreateWorkspaceFlow`):

- Atajo `Mod+Shift+N` (`KeyboardActionId.createWorkspace`): `lib/src/features/keyboard/application/keyboard_command_dispatcher.dart:73`. El proyecto inicial es el proyecto activo.
- Sidebar (botón y menú del proyecto, "New Workspace"): `lib/src/features/workbench/presentation/project_workbench_sidebar_actions.dart:41`.
- Dashboard de bienvenida: `lib/src/features/workbench/presentation/welcome_dashboard_columns.dart:89`.
- El reintento de un job fallido reabre el formulario con el snapshot guardado: `background_setup_job_host.dart:72-83`.

Flujo (`workbench_dialog_launchers_create_workspace.dart:32-250`, `prompt_workspace_dialog.dart`, `application/background_setup_jobs.dart:100-260`, `application/prompt_workspace_pipeline.dart`):

1. **Proyecto**: no se infiere. Se usa `initialProject` (el proyecto activo, o el de la fila del sidebar) o, si falta, el primero de `sortProjectsForSelection` (`prompt_workspace_dialog.dart:208`). El usuario puede cambiarlo.
2. **Perfil**: `settings.agents.defaultAgentProfileId`, guardado en el runtime como `runtimeSettings.defaultAgentProfileId` (`runtime_settings_repository.dart:63`); si no hay, el primero de la lista (`_defaultAgentProfile`, `prompt_workspace_dialog.dart:195`).
3. **Modo**: por defecto en la carpeta del proyecto (`initialUseProjectCheckout: … ?? true`, línea 197). Si el proyecto no es repo Git, fuerza la carpeta del proyecto.
4. **Rama origen** (solo worktree): `projectConfig.newWorkspace.preferredSourceBranch` y luego `pickDefaultSourceBranch` sobre el catálogo de ramas del host (`prompt_workspace_dialog_branch_loading.dart:28-42`).
5. **Sección automática**: activada por defecto (`initialAutoAssignSection: … ?? true`) cuando el runtime soporta secciones y existe al menos una (`hasWorkspaceSections`).
6. **Pipeline** (`PromptWorkspacePipeline.run`), que se ejecuta como job en segundo plano:
   1. `aiText.workspaceIdentity.generate` con `projectId`, `prompt` y `autoAssignSection`. Timeout de 11 min.
   2. Comprueba colisiones de la rama generada contra las ramas de workspaces activos y `git.branchExists` o el catálogo del host. Si choca, repite **una vez** pidiendo "a different workspace name and branch".
   3. `workspace.createShared` o `workspace.createManaged` con `deferSetup: true`, sin abrir terminal (`createWorkspaceForPrompt`, `workbench_controller_workspace_creation.dart:45`). Un error con aspecto de colisión también provoca un reintento.
   4. Si hay `sectionId`, `workspaceSection.setForWorkspace`, en modo best-effort.
   5. `agentProfile.launchIdempotent` con `clientMutationId`; usa `agentProfile.launch` si el host es antiguo (`infra/prompt_workspace_runtime_client.dart:68-125`).
   6. `completePromptWorkspaceCreation`: siembra el panel, abre la tab **Setup** diferida y activa la tab del agente.
   7. Si el lanzamiento falla, el snapshot conserva `created` y `clientMutationId` para reintentar el lanzamiento sin crear otro workspace.

Mobile repite el mismo pipeline en Dart (`mobile/lib/src/features/workbench/application/prompt_workspace_pipeline.dart`, mismos dos intentos y la misma lógica de colisión). El setup diferido arranca con `terminal.create` (`deferred_workspace_setup_launcher.dart`).

### 6.2 Qué está en backend y qué solo en UI

| Paso | Dónde vive | ¿Reutilizable desde MCP? |
|---|---|---|
| Inferir el proyecto desde el prompt | **No existe** en ningún sitio | No |
| Nombre y rama del workspace | Runtime host: `terminal_host/server/ai_assist_requests.rs:50` y `ai_assist_workspace_identity.rs:35-169` (prompt al agente de AI Assist) | Sí (RPC `aiText.workspaceIdentity.generate`, capability `aiAssistWorkspaceIdentity`) |
| Sección más adecuada con fallback "Others" | Mismo servicio: con `autoAssignSection=true` incluye la lista de secciones; si la respuesta es "Others", desconocida o vacía, no devuelve `sectionId` (`ai_assist_workspace_identity.rs:151-166`) | Sí, pero **el CLI no envía `autoAssignSection`** (`workspace_start.rs:307-316`) |
| Perfil por defecto | Runtime (`runtimeSettings.defaultAgentProfileId`; ya lo usa `voice_home_agent.rs:234`) | Sí, aunque ni el CLI ni el MCP lo usan: el perfil es obligatorio |
| Rama origen preferida | Runtime: `worktree_setup::preferred_source_branch` se aplica en `managed_workspace.rs:139-141` cuando falta `sourceBranch` | Sí, pero **el CLI rechaza la falta de `--source-branch` antes de llegar al host** (`workspace_start.rs:214-220`) |
| Colisiones y reintento de identidad | **Duplicado** en Dart desktop y Dart mobile | No (el CLI no reintenta) |
| Setup diferido en una tab Setup | **Solo UI** (desktop y mobile abren la terminal) | No: el CLI no envía `deferSetup`, así que el setup corre **en línea** (`managed_workspace.rs:49-54`, el comentario lo confirma) |
| Asignar sección | RPC `workspaceSection.setForWorkspace` | Sí (el CLI lo hace solo con `--section` explícito) |
| Lanzamiento idempotente | RPC `agentProfile.launchIdempotent` | Sí, el CLI acepta `--client-mutation-id`, pero el MCP no lo pasa |

Conclusión: la orquestación de New Workspace from Prompt **no es un servicio backend**. Es lógica de cliente duplicada en desktop (Dart), mobile (Dart) y CLI (Rust, `workspace_start.rs`). Solo la generación de identidad y sección, el perfil por defecto y la rama preferida están en el runtime y se pueden reutilizar tal cual.

### 6.3 Divergencias de `start_agent_workspace` frente a la UI

| # | Aspecto | UI (desktop y mobile) | `start_agent_workspace` (`workspace start`) | Impacto |
|---|---|---|---|---|
| D1 | Proyecto | Proyecto activo o el que elige el usuario | `projectId` obligatorio (o `workspaceId` para inferirlo) | El cliente MCP tiene que decidir el proyecto; nadie lo infiere |
| D2 | Sección | Automática por IA con fallback a "Others" (activada por defecto) | Solo `section` explícita por nombre; nunca envía `autoAssignSection` | No replica la UI |
| D3 | Perfil | Perfil por defecto del runtime | `profile` obligatorio | El cliente tiene que elegirlo |
| D4 | Rama origen | `preferredSourceBranch` del proyecto o rama por defecto del catálogo | Obligatoria con `worktree` y `projectId`; el CLI falla antes de que el host aplique su propio default | Fricción y errores evitables |
| D5 | Colisiones | Comprueba la rama y reintenta la identidad una vez | Sin comprobación previa; `createManaged` falla con "already exists" | Fallo donde la UI se recupera sola |
| D6 | Setup del worktree | Diferido a una tab Setup visible, después del lanzamiento | En línea y bloqueante **antes** de lanzar el agente | Más latencia; riesgo de timeout (R1) |
| D7 | Idempotencia | `launchIdempotent` con `clientMutationId` y reintento del lanzamiento sin recrear | El MCP no pasa `--client-mutation-id`; un fallo de lanzamiento deja el workspace creado y devuelve error | Duplicados al reintentar |
| D8 | Padre | Elegible | Siempre `--no-parent` | Falta jerarquía |
| D9 | Modo por defecto | Carpeta del proyecto (`useProjectCheckout = true`) | Carpeta del proyecto salvo `worktree: true` | Igual |
| D10 | Timeout | Job en segundo plano sin límite práctico (identidad hasta 11 min) | 58 s por llamada MCP; el ejecutor mata el CLI hijo (`kill_on_drop`) | Workspace a medio crear posible (R1) |

### 6.4 Propuesta técnica (no implementada)

Objetivo: una herramienta MCP, por ejemplo `start_workspace_from_prompt`, que reciba solo `prompt` y, opcionalmente, `projectId`, `profile`, `worktree`, `sourceBranch`, `section` y `hostId`. Debe reproducir exactamente el flujo de la UI sin que el cliente replique lógica, devolver enseguida un `operationId` y permitir seguir el progreso con una herramienta de espera.

**Recomendación: mover la orquestación al runtime host como un servicio con estado.**

1. **Nuevo RPC `workspace.startFromPrompt` en el runtime host** (Rust), como operación diferida igual que `aiText.workspaceIdentity.generate`, con registro de operaciones y cancelación. Pasos:
   1. Resolver el proyecto (ver punto 2).
   2. Resolver el perfil: el explícito o `defaultAgentProfileId`; si no hay, el primero.
   3. Resolver la rama origen: la explícita, `preferred_source_branch` o la rama por defecto del repo.
   4. Generar la identidad con `autoAssignSection=true` reutilizando `generate_workspace_identity`.
   5. Comprobar colisiones con el mismo criterio que la UI y reintentar una vez con el sufijo de reintento.
   6. `createManaged` o `createShared` con `deferSetup: true`.
   7. Asignar la sección en modo best-effort.
   8. Lanzar con `launchIdempotent` usando un `clientMutationId` derivado del `operationId`.
   9. Persistir un registro con `created`, `clientMutationId` y la fase, para reanudar o reintentar el lanzamiento sin recrear.

   El setup diferido queda como tab Setup con su comando, que la app abre al sincronizar. Para un cliente sin UI hace falta decidir si el host arranca la terminal de setup por sí mismo (como hace mobile con `terminal.create`), lo cual es recomendable para que el workspace quede igual que desde la UI.
2. **Inferencia de proyecto** (nueva y opcional cuando falta `projectId`): ampliar el prompt de identidad con la lista de proyectos (nombre y ruta, acotados como se hace hoy con las secciones) y un campo `project` validado contra esa lista sin distinguir mayúsculas. Si falla, usar el **proyecto del workspace más reciente** (`workspaceActivity`) o, si hay un solo proyecto, ese. Si sigue siendo ambiguo, devolver error con los candidatos en vez de adivinar. Coste: una sola llamada de IA, porque proyecto, nombre, rama y sección se generan juntos. El proyecto debe resolverse antes de calcular colisiones y rama origen, así que la respuesta se valida en ese orden.
3. **CLI**: añadir `alera workspace start-from-prompt` (o `workspace start --auto` y `--auto-section`), que llame al RPC y espere con `--wait` o devuelva el `operationId`. Además, `workspace start` debería dejar de exigir `--source-branch` y delegar el default al host (corrige D4 también para el MCP actual).
4. **MCP**: dos herramientas:
   - `start_workspace_from_prompt` (execute): devuelve `operationId` y la fase inicial en menos de 50 s.
   - `wait_for_workspace_start` (read): espera hasta 50 s y devuelve la fase, el `workspaceId` o el `tabId`, o el error.

   Así se cumple el contrato de esperas acotadas del catálogo (`MAX_WAIT_SECONDS`) y se elimina R1. Hay que regenerar `edge/src/mcp/tool_catalog.json`.
5. **GUI desktop y mobile**: migrar progresivamente `PromptWorkspacePipeline` a un cliente fino del nuevo RPC, conservando los fallbacks para hosts antiguos (detección por capability, como hoy con `launchIdempotent`). Así hay una sola implementación y el MCP queda idéntico a la UI por construcción.

**Alternativa de menor coste (paso intermedio)**: dejar la orquestación en el CLI y corregir `workspace_start.rs`:
- enviar `autoAssignSection` cuando no haya `--section` explícita y asignar el `sectionId` devuelto
- reintentar la identidad ante colisión
- no exigir `--source-branch`
- usar `deferSetup: true` y arrancar la terminal de setup
- el MCP pasaría un `--client-mutation-id`
- el perfil sería opcional, tomando el del runtime

Resuelve D2 a D5, D7 y parte de D6, pero no D10 (sigue siendo síncrono y limitado a 58 s) ni D1, y añade una tercera copia de la lógica de colisiones. Recomendable solo como mitigación rápida.

**Prioridad recomendada**:

1. **P1**: corregir los defaults de `workspace start` y la idempotencia del MCP. Es pequeño y reduce fallos ya.
2. **P1**: RPC `workspace.startFromPrompt` con operación asíncrona, más las dos herramientas MCP.
3. **P2**: inferencia de proyecto en el mismo prompt de identidad.
4. **P2**: migrar desktop y mobile al RPC para eliminar la duplicación.

Pruebas a añadir en cualquier implementación:

- paridad de sección ("Others" o una desconocida deja el workspace sin sección)
- colisión con reintento
- reintento del lanzamiento sin recrear el workspace
- timeout del cliente MCP sin dejar un workspace huérfano
- host antiguo sin capability

## 7. Riesgos

| # | Riesgo | Evidencia | Severidad | Mitigación sugerida |
|---|---|---|---|---|
| R1 | `start_agent_workspace` puede agotar su timeout de 58 s mientras genera la identidad con IA (el CLI le da hasta 11 min) o mientras corre el setup en línea. El ejecutor mata el CLI hijo, y el workspace puede quedar creado sin agente o la creación seguir en el host sin que el cliente lo sepa. **Es una inferencia del código; no la reproduje.** | `mcp_tools/catalog_execute.rs:11` (`LAUNCH_TIMEOUT` = 58), `executor.rs:92,122-130`, `workspace_start.rs:13`, `managed_workspace.rs:49-54` | Alta | Operación asíncrona con `operationId` (6.4), o como mínimo `deferSetup` e idempotencia |
| R2 | El MCP no envía claves de idempotencia en `start_agent_workspace` ni en `launch_agent`; un reintento tras timeout o error duplica workspaces o agentes | `catalog_execute.rs` (no usa `--client-mutation-id`) | Media-alta | Derivar un `clientMutationId` del id de la llamada MCP o aceptarlo como argumento |
| R3 | `alera mcp serve` local expone todas las herramientas de ejecución salvo `--read-only` e ignora `settings.mcp.access`, aunque MCP Control esté en "Off" | `mcp_commands.rs:52`, `stdio_server.rs:144` | Media. Es coherente con que el usuario local ya tiene el CLI, pero sorprende | Documentarlo, o respetar `access` también en local con un flag de override |
| R4 | `write_terminal` permite escribir en **cualquier** terminal, incluidas las shells del usuario: en acceso full equivale a ejecutar comandos arbitrarios | `catalog_execute.rs:209` | Alta (por diseño) | Opción para restringirlo a terminales con agente, y avisarlo en la UI de MCP Control |
| R5 | `list_tabs` y `show_terminal` devuelven el payload completo de lanzamiento (argv del perfil, por ejemplo `--permission-mode bypassPermissions`, ids de sesión) a clientes cloud. En la muestra no encontré claves ni tokens | Salida de `alera tab --json list` | Baja-media | Filtrar el payload en la proyección MCP (`omit_fields`) |
| R6 | Desfase entre el catálogo estático del edge y la versión del runtime: una herramienta nueva aparece en el edge y falla con `tool_unavailable` en runtimes antiguos | `relay_mcp.rs:218-223`, `edge/src/mcp/tools.ts` | Baja | Ya mitigado con un mensaje claro; versionar el catálogo por runtime si crece |
| R7 | `cancel_task` siempre cancela de forma administrativa (`--force`) | `catalog_execute.rs:300` | Baja (auditado con el prefijo `[mcp]`) | Mantenerlo marcado como destructivo |
| R8 | `delegate_task` espera la aceptación hasta 50 s; con perfiles lentos devuelve error aunque la tarea siga viva (`--keep-on-failure`) | `catalog_execute.rs:158` | Media | Devolver la tarea creada aunque no haya aceptación y seguirla con `wait_for_task` |
| R9 | Exponer lectura de archivos, git o PRs (P2) envía código fuente a clientes cloud | — | Media | Herramientas separadas, solo en acceso full o con un scope dedicado |

## 8. Hallazgos colaterales (fuera del MCP)

1. **Bug probable en mobile**: Recovery llama a `workspace.runSetup` (`mobile/lib/src/features/runtime/infra/mobile_runtime_recovery_client.dart:111`), pero ese método **no está** en `mobile_request_allowed` (`terminal_host/server/mobile_gateway_surface.rs:180-182` solo incluye `prepareRelocationSetup`, `recoverRelocationSetup` y `cancelRelocationSetup`), y el handler lo comprueba (`deferred_workspace_setup.rs:19`). Desde el teléfono, "Run Saved Setup" debería fallar con "Mobile clients cannot call terminal host request". El From Prompt de mobile no se ve afectado, porque usa `terminal.create`.
2. `codex.*` aparece en la barrera de mutaciones (`runtime_mutation_barrier.rs:99`) pero no tiene handler: es código muerto.
3. Varios verbos están permitidos para mobile pero la app no los usa (`aiAssist.complete`, `workspace.storageImpact`, `automation.purge`, entre otros): es superficie expuesta sin uso.

## 9. Recomendación priorizada

**P1**

1. Corregir los defaults de `workspace start` y la idempotencia del MCP; después, el RPC `workspace.startFromPrompt` asíncrono con `start_workspace_from_prompt` y `wait_for_workspace_start` (sección 6.4). Resuelve R1 y R2.
2. Secciones: `list_sections`, `set_workspace_section` y `clear_workspace_section`.
3. `rename_workspace`.
4. `list_project_branches` (requiere un comando CLI nuevo sobre `project.branches.list`).
5. `show_workspace_issue` y Watch and Fix: `show_pr_watch`, `start_pr_watch`, `stop_pr_watch`.
6. Automations: `show_automation`, `show_automation_run`, `cancel_automation_run`.
7. `cancel_question` del inbox.

**P2**

8. Ciclo de vida de workspaces: `archive/unarchive`, `remove_workspace` (destructivo, con preflight), `hand_off/hand_on`, tags y relaciones.
9. Tabs y terminales: `create_tab`, `close_tab`, `restart_terminal`.
10. Lectura de git, PR, archivos y búsqueda (requiere CLI nuevo; ver R9).
11. `version`, cuotas de agentes, snapshot de recursos y `ssh-target list/status`.
12. Ampliar los parámetros de `create_workspace`, `launch_agent`, `run_automation` y `list_automations`.
13. Decision gates y run policy en solo lectura; gestión de automations (pausar, reanudar, crear o editar, readiness, preview).

**P3**: el resto de la sección 4.

**No exponer**: cuenta, mobile pairing, gestión de MCP Control, alta y bootstrap de SSH, `runtime clear`/`stop`, `orchestration reset`, purgas y decisiones humanas (gates, run policy, aprobación de workflows), salvo con un mecanismo explícito de confirmación humana.

## 10. Método

- Catálogo MCP: lectura completa de `rust/alera-cli/src/mcp_tools/*`, `mcp_commands.rs`, `mcp_settings.rs`, `terminal_host/relay_mcp.rs` y `edge/src/mcp/*`. Comprobé que `alera mcp --json tools` y `edge/src/mcp/tool_catalog.json` tienen las mismas 31 herramientas.
- CLI: recorrido recursivo de `alera --help` (unos 200 subcomandos) y de las opciones de cada comando que el MCP envuelve.
- GUI: inventario de acciones de `lib/` (registro `KeyboardActionId`, menús, diálogos, controladores y repositorios) y de `mobile/lib`, más el despachador RPC del host (`terminal_host/server/*`) y su allowlist mobile.
- New Workspace from Prompt: lectura directa de los archivos citados en la sección 6.
- Limitaciones: es un análisis estático y no ejecuté ninguna herramienta MCP. R1 es una inferencia del código. Los números de línea corresponden a `c8b3d3984`.

## 11. Comunicación bidireccional y eventos con clientes MCP externos

Esta sección se añadió a pedido de un cliente MCP externo. La pregunta: cómo hacer más fluida la coordinación (ask_agent, avisos de respuesta, estados de entrega y lectura, push en lugar de polling), qué soporta hoy el servidor, qué pueden recibir de verdad los clientes y cómo lo resuelve EducUp con "MCP Events". Es solo investigación.

### 11.1 Qué soporta hoy el servidor MCP de Alera (verificado en código)

| Capacidad MCP | `alera mcp serve` (stdio) | Edge `/v1/mcp` (remoto) | Evidencia |
|---|---|---|---|
| Versiones de protocolo | `2025-11-25`, `2025-06-18`, `2025-03-26` | Las mismas | `mcp_tools/stdio_server.rs:15`, `edge/src/mcp/protocol.ts` |
| Capabilities anunciadas | Solo `tools: { listChanged: false }` | Igual | `stdio_server.rs:165`, `edge/src/mcp/endpoint.ts:121` |
| Métodos | `initialize`, `ping`, `tools/list`, `tools/call` | Igual | `stdio_server.rs:65-125`, `endpoint.ts:117-137` |
| Notificaciones cliente → servidor | Solo `notifications/cancelled` (mata el proceso hijo) | Toda notificación responde `202` y se descarta; la cancelación real ocurre al abortarse el HTTP (`mcp.cancel` al runtime) | `stdio_server.rs:56-63`, `endpoint.ts:195`, `relay_calls.ts:128-131,154-162` |
| Notificaciones servidor → cliente (`progress`, `resources/updated`, `tools/list_changed`, `message`) | Ninguna | Ninguna | No existe el código |
| Peticiones servidor → cliente (elicitation, sampling, roots) | Ninguna | Ninguna | No existe el código |
| Resources, prompts, `resources/subscribe` | No | No | `-32601 Method not found` |
| Streaming (SSE en POST o GET), `Mcp-Session-Id`, reanudación con `Last-Event-ID` | No; JSON línea a línea | No: "stateless Streamable HTTP", `GET` y `DELETE` responden `405`, solo `application/json` | `endpoint.ts:35,146-148`, `docs/remote-mcp.md` (Edge MCP Endpoint) |
| Llamadas largas | Esperas de 50 s como máximo (`MAX_WAIT_SECONDS`); el cliente vuelve a llamar | Igual, y la llamada al DO tiene tope de 10 min | `mcp_tools/mod.rs:28`, `relay_calls.ts:7` |
| `structuredContent` | No; el resultado es texto JSON | Solo en `list_runtimes` (`toolJson`); las herramientas del runtime devuelven texto | `executor.rs` (`to_mcp`), `protocol.ts` |

Conclusión: es un servidor de **solo tools, request/response y sin estado**. La única forma de "esperar" eventos es el polling acotado (`wait_for_reply`, `wait_for_task`, `wait_for_terminal`). El diseño es deliberado: `docs/remote-mcp.md` dice que el edge "is stateless: it builds no MCP session" y que las esperas se limitan porque los clientes hospedados abandonan una llamada HTTP al cabo de un minuto.

### 11.2 Ciclo de vida de `ask_agent` y correlación de IDs

- **Alta**: `ask_agent` ejecuta `inbox ask --inbox ext:mcp`. La pregunta se guarda como mensaje de orquestación con prioridad `high` por defecto. Caduca a las 5 h si nunca se entrega (configurable entre 60 s y 7 días) y cada destinatario admite como mucho 20 preguntas sin entregar (`alera-core/src/runtime/inbox_models.rs:9-13`).
- **Entrega**: se inyecta en el terminal del agente cuando termina su turno, como un bloque "Orchestration Messages" con la instrucción `alera orchestration reply --id …`. Al entregarse queda `delivered_at`.
- **Estados**, por orden de precedencia (`inbox_queries.rs:243-258`):
  - `cancelled`
  - `answered`: llegó un `reply` con `reply_to_id`
  - `expired`: caducó sin entregarse
  - `delivered`: pegada en el terminal
  - `received`: marcada como leída antes de pegarse, por ejemplo con `orchestration check`
  - `pending`
- **Correlación**:
  - `questionId` es el id del mensaje y `threadId` el id de la pregunta raíz.
  - Las repreguntas usan `threadId` y las respuestas llevan `reply_to_id`.
  - `wait_for_reply` devuelve el hilo completo, los mensajes nuevos posteriores a `after` y un `cursor` (secuencia monotónica).
  - Resultados posibles: `answered`, `message`, `cancelled`, `expired`, `purged` y `timeout` (`terminal_host/server/inbox_wait.rs`).
- **Fiabilidad de la espera**: es **reanudable sin pérdidas**. El estado vive en la base del runtime y el cursor es una secuencia. Si una respuesta HTTP se pierde, repetir la llamada con el mismo `after` devuelve lo mismo. Al vencer el plazo se relee la base, así que no se pierde una respuesta que llegue en el límite.
- **Lectura**: no hay acuse explícito desde MCP. `wait` y `show` marcan como leído lo que devuelven (`mark_returned_read`), lo que actualiza `unread_reply_count`.
- **Avisos que ya existen**:
  - Cada respuesta a un inbox externo encola un push para el móvil del usuario (`PushEvent::inbox_reply`, `push_delivery.rs:110-124`).
  - Los clientes locales reciben el evento `inboxChanged` con una revisión (`inbox_requests.rs:72-75`).
  - Ninguno de los dos llega a un cliente MCP.

Brechas detectadas:

| # | Brecha | Efecto | Prioridad |
|---|---|---|---|
| C1 | Todos los clientes MCP de la cuenta comparten el inbox `ext:mcp`, y `external_meta.origin` no guarda el cliente OAuth, el grant ni la conversación (el CLI hijo corre como cliente local y `executor.rs` borra el contexto) | ChatGPT puede listar y leer los hilos de Claude.ai y viceversa; el agente ve "from ext:mcp" sin saber quién pregunta | P1 |
| C2 | El RPC `inbox.wait` admite esperar un inbox entero, pero el MCP solo expone la espera por `questionId` | Con varias preguntas abiertas, el cliente tiene que sondear cada una | P1 |
| C3 | No hay `cancel_question` ni acuse de lectura explícito | Sin forma de retirar una pregunta o confirmar que se procesó | P1 |
| C4 | `ask_agent` no admite clave de idempotencia | Un reintento tras un timeout duplica la pregunta | P1 |
| C5 | Una pregunta `delivered` sin respuesta no caduca; solo caducan las no entregadas, y solo cuenta como respuesta un `orchestration reply` | Si el agente la ignora, el cliente espera indefinidamente | P2 |
| C6 | Resultados como texto, sin `structuredContent` | Encadenar `cursor` y `questionId` depende de que el modelo lea bien el JSON | P2 |
| C7 | Cada sondeo pasa por edge, nube, DO y runtime, y lanza un proceso CLI | Coste y límite de tasa por token (`MCP_LIMITER`) | P3 |

### 11.3 Qué pueden recibir los clientes (soporte de cliente)

- **Especificación MCP**:
  - Hasta `2025-11-25`, las notificaciones servidor → cliente (`notifications/resources/updated` tras `resources/subscribe`, `progress`, `list_changed`) solo llegan por una conexión o stream abierto (stdio, o SSE en Streamable HTTP con sesión).
  - La versión `2026-07-28` [elimina las sesiones a nivel de protocolo](https://blog.modelcontextprotocol.io/posts/2026-07-28/), añade `server/discover` y mueve las notificaciones de cambio a un único stream `subscriptions/listen`.
  - También reemplaza la elicitation iniciada por el servidor por Multi Round-Trip Requests (`resultType: "input_required"`), pasa Tasks a la extensión `io.modelcontextprotocol/tasks` (con `tasks/get` por polling) y depreca Roots, Sampling y Logging.
  - **Una notificación MCP no inicia por sí misma un turno del modelo.** Que el modelo "despierte" depende de cada cliente.
- **ChatGPT**:
  - Consume tools y MCP Apps.
  - Según la documentación de un gateway externo, "doesn't currently consume arbitrary MCP prompts, roots, sampling, or elicitation" ([Zuplo](https://zuplo.com/docs/mcp-gateway/connect-clients/chatgpt.md)).
  - Una respuesta en la [comunidad de OpenAI](https://community.openai.com/t/does-chatgpt-apps-support-reading-standard-mcp-resources/1384027) indica que los resources estándar no llegan al agente.
  - No encontré ninguna fuente que confirme soporte de `resources/subscribe`, de notificaciones o de `progress`.
  - Para avisar a ChatGPT de forma asíncrona está [OpenAI MCP Events](https://developers.openai.com/plugins/build/mcp-events): es **solo webhook** (polling, streaming y SSE "are not part of this integration"), exige MCP `2026-07-28`, un plugin y almacenamiento persistente de suscripciones, y funciona en Work chats. Según OpenAI se basa en un "draft MCP Events design sketch", así que no es parte del estándar. ChatGPT procesa el evento de forma asíncrona como una ejecución de tarea en el chat suscrito.
- **Otros clientes** (Claude.ai, Claude Desktop, Claude Code, Cursor): no verifiqué en esta investigación si reaccionan a notificaciones o suscripciones. Hay que tratarlo como desconocido hasta probarlo.
- Conclusión: **hoy ningún mecanismo MCP estándar despierta a ChatGPT.** El polling acotado funciona en todos los clientes. MCP Events es la única vía de push hacia ChatGPT, y no es estándar ni está probada de extremo a extremo (ver 11.4).

### 11.4 Referencia local: "MCP Events" de EducUp (no estándar)

Fuente: `~/Projects/educup/educup-automations` (commit `77b23b0`, 2026-10-03), `docs/mcp-events.md`, `docs/mcp-events-implementation.md`, `src/services/educup_mcp/events.py`, `src/shared/mcp_events/` y las Lambdas `mcp_event_publisher`, `mcp_event_delivery` y `mcp_event_reconciler`.

- **Contrato**: el de OpenAI MCP Events.
  - `events.py` registra los métodos propios `events/list`, `events/subscribe` y `events/unsubscribe` en el SDK de Python.
  - Inyecta `capabilities.events` en la respuesta de `server/discover` solo con `2026-07-28`.
  - Un único evento, `approval.outcome`, con un payload mínimo (`approval_id`, `operation_id`, `status`, `attempt`, `receipt_version`). El evento solo es una pista: la verdad se lee con la tool `operation_status`.
- **Arquitectura**:
  - El publicador deriva eventos deterministas del stream de Operations.
  - Tres tablas DynamoDB (suscripciones, eventos y recibos de entrega), con TTL de 24 h.
  - SQS solo transporta referencias.
  - El worker de entrega reclama con un lease de 45 s, revalida el usuario, su rol y la familia OAuth, y firma con Standard Webhooks.
  - Un reconciliador por minuto rellena huecos y reencola entregas.
- **Seguridad y reintentos**:
  - Callbacks solo por HTTPS:443, con resolución DNS a IPs públicas fijadas, sin redirecciones y con un challenge firmado.
  - Secretos cifrados con KMS.
  - Plazo de 10 s por intento y reintentos exponenciales de 5 s a 15 min, hasta 12 intentos.
  - `410` detiene la suscripción y `413` deja el recibo como muerto.
- **Reanudación**: un cursor opaco reproduce todo el historial retenido (24 h) y los recibos evitan reenviar lo ya acusado. Un cursor más antiguo responde `truncated: true`.
- **Estado real**: activado el 2026-09-30. ChatGPT muestra `approval.outcome` entre sus "Tools and events" y llegó a llamar a `events/subscribe`. **Todavía no se ha observado** un callback real con continuación en el chat, y el seguimiento por defecto "has not yet been demonstrated". Por eso se mantiene el flujo de consulta manual.
- **Lecciones para Alera**:
  1. Es una inversión de infraestructura considerable (tablas, colas, reconciliador, KMS, defensas SSRF).
  2. El payload debe ser mínimo y llevar a una tool de lectura.
  3. La reanudación por cursor con recibos es imprescindible.
  4. Hay que conservar el polling como camino principal hasta demostrar la continuación en el cliente.

### 11.5 Propuesta, separando servidor y cliente

**Servidor (Alera), por prioridad:**

- **P1: mejoras que sirven a cualquier cliente sin protocolo nuevo**:
  1. **Identidad y aislamiento por cliente**:
     - Pasar al CLI hijo, con una variable propia y no las de `CONTEXT_VARIABLES`, los claims de la llamada que ya verifica `relay_mcp.rs` (`clientId`, `clientName`, `grantId`).
     - Usar un inbox por grant (`ext:mcp-<grant>`) o filtrar por origen.
     - Guardar `origin: { surface: "mcp", clientName }` para que el agente sepa quién pregunta.
     - Resuelve C1.
  2. **`wait_for_inbox`**: espera a nivel de inbox con `cursor`, sobre el RPC `inbox.wait` que ya existe. Una sola espera cubre todas las preguntas del cliente (C2).
  3. **`cancel_question` y `mark_thread_read`**, sobre `inbox cancel` e `inbox read` (C3).
  4. **Idempotencia**: un `clientRequestId` opcional en `ask_agent`, y también en `launch_agent` y `start_agent_workspace` (C4 y R2).
  5. **`structuredContent`** con `outcome`, `cursor`, `questionId`, `threadId` y `nextAction` en las herramientas de espera (C6).
- **P2: servicio de las preguntas**:
  6. Plazo de respuesta para preguntas entregadas (`answerBy`), con un estado `stale` y un recordatorio automático al agente (C5).
  7. Exponer el estado "el agente está trabajando" (agent presence) en `show_inbox_thread`.
- **P2: MCP estándar con streaming, útil para clientes locales o IDE y no para ChatGPT**:
  8. En `mcp serve` (stdio), anunciar `resources` con `subscribe` para `alera://inbox/<inbox>` y `alera://question/<id>`, y emitir `notifications/resources/updated` a partir del evento `inboxChanged` del host. Requiere que el servidor mantenga una conexión de eventos con el runtime; hoy lanza un CLI por llamada.
  9. `notifications/progress` en las herramientas largas cuando el cliente envía `progressToken`.
  10. Migrar el edge a `2026-07-28`. Encaja con su diseño sin sesiones, y `server/discover` es requisito previo para MCP Events. Lo siguiente sería evaluar la extensión Tasks como sustituto estándar de `wait_*`.
- **P3 (o P2 si ChatGPT confirma la continuación)**: implementar **OpenAI MCP Events** en la nube y el edge, no en el runtime.
  - **Eventos**: `inbox.reply` (`runtimeId`, `threadId`, `questionId`, `cursor`), `orchestration.task.state`, `automation.run.finished` y `workspace.start.finished`.
  - **Fuente**: el runtime ya genera `PushEvent::inbox_reply` para las respuestas a inboxes externos y lo envía a la nube para el push móvil (`push_delivery.rs:110-124`). La nube haría el fan-out a las suscripciones webhook en Postgres, con recibos, reintentos, Standard Webhooks, defensas SSRF y una ventana de reanudación de 24 h.
  - **Payload**: solo identificadores. El cliente continúa con `show_inbox_thread` o `wait_for_reply` usando el cursor.
  - **Requisitos**: protocolo `2026-07-28` y `server/discover` en el edge, un plugin de ChatGPT y Work chats.
  - **Riesgo**: la continuación en el cliente no está demostrada (11.4).
- **Alternativa no MCP**: webhooks salientes genéricos configurados por el usuario (Slack, n8n, un endpoint propio) para respuestas del inbox y fin de tareas o automations. Usaría la misma infraestructura de fan-out y no depende de ningún cliente MCP.

**Cliente (lo que debe soportar el cliente MCP):**

| Mecanismo | Qué necesita el cliente | Estado conocido |
|---|---|---|
| Polling acotado (`wait_*` + cursor) | Solo tools | Funciona en todos los clientes, incluido ChatGPT (esta conversación lo demuestra) |
| `resources/subscribe` y notificaciones | Conexión o stream persistente y lógica para reaccionar | No soportado o sin confirmar en ChatGPT; sin verificar en el resto |
| `subscriptions/listen` (`2026-07-28`) | Cliente con la versión nueva | Sin verificar |
| Elicitation y MRTR | Formularios en el cliente | ChatGPT no consume la elicitation estándar (tiene una extensión propia, `openai/elicitation/create`, según fuentes de terceros) |
| OpenAI MCP Events | ChatGPT Work chats, plugin y tarea activada por eventos | Disponible según OpenAI; continuación real sin demostrar (EducUp) |

**Fiabilidad ante desconexiones (estado actual):**

| Escenario | Qué pasa |
|---|---|
| El cliente se desconecta durante `wait_*` | La llamada se cancela (`mcp.cancel` o fin del stdin); no se pierde nada porque el estado vive en el runtime; se reanuda con el mismo `cursor` |
| Runtime offline | `runtime_offline`; las preguntas pendientes siguen en la base local |
| Reinicio del runtime durante una espera | Se pierden las esperas en memoria; el cliente vuelve a llamar con el cursor y recupera lo nuevo |
| Reintento de `ask_agent`, `launch_agent` o `start_agent_workspace` | Duplica la operación (C4, R2) |
| Webhook caído (si se implementa MCP Events) | Hace falta reanudar por cursor con retención y recibos, como EducUp |

**Recomendación priorizada:**

1. P1, unos 2-4 días de trabajo estimados: C1 a C4 y C6 (identidad por cliente, `wait_for_inbox`, `cancel_question`, idempotencia, `structuredContent`). Mejora la coordinación en todos los clientes ya.
2. P2: plazo de respuesta y recordatorios (C5); `resources/subscribe` y `progress` en stdio para clientes locales; migrar el edge a `2026-07-28`.
3. P3, condicionado: OpenAI MCP Events reutilizando el flujo push existente, solo cuando EducUp (u otra prueba) demuestre que ChatGPT continúa el chat al recibir un callback. Hasta entonces el polling acotado sigue siendo el camino principal.

Fuentes externas consultadas el 2026-10-10:

- [OpenAI: MCP Events](https://developers.openai.com/plugins/build/mcp-events)
- [MCP Blog: The 2026-07-28 Specification](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [Zuplo: Connect ChatGPT](https://zuplo.com/docs/mcp-gateway/connect-clients/chatgpt.md)
- [OpenAI Community: standard MCP resources in ChatGPT Apps](https://community.openai.com/t/does-chatgpt-apps-support-reading-standard-mcp-resources/1384027)
