# Inconvenientes del sistema de orquestación de Alera

Documento de retroalimentación para pulir `alera orchestration`. Recoge problemas concretos observados al delegar una tarea real en un agente Codex (OpenAI Codex v0.145.0) sobre este repositorio, con evidencia, impacto y propuesta de arreglo por cada punto.

Estado al 2026-07-23: los once puntos fueron atendidos en la implementación descrita en la sección "Resolución implementada". La evidencia original se conserva para explicar el motivo de cada cambio.

Entorno observado:

- `cliVersion` 0.1.0, `runtimeHostVersion` 0.1.0, `orchestrationProtocolVersion` 2, `dispatchPreambleVersion` 2.
- `cliCommit` y `runtimeHostCommit`: `unknown`.
- Agente worker: OpenAI Codex v0.145.0 (`gpt-5.6-sol high`, modo YOLO).

## Resumen priorizado

| # | Problema | Severidad | Área |
| - | - | - | - |
| 1 | La detección de readiness no reconoce el TUI de Codex, `agent-spawn` da timeout | Alta | Detección de agente |
| 2 | El único camino que funciona con Codex es el dispatch manual | Alta | Flujo de dispatch |
| 3 | `terminal write --enter` no somete el prompt en el TUI de Codex | Alta | Entrega de preámbulo |
| 4 | Intentos fallidos de spawn dejan terminales huérfanos sin limpieza | Media | Ciclo de vida |
| 5 | Mensaje de error apunta a un flag que no existe en ese comando | Media | Ergonomía CLI |
| 6 | No hay forma de esperar la finalización sin polling manual | Media | Observabilidad |
| 7 | `terminal-wait --for dispatch-accepted` da timeout aunque la aceptación ocurre | Media | Observabilidad |
| 8 | El preámbulo (5451 chars) no es práctico para pegar en un TUI | Media | Entrega de preámbulo |
| 9 | Inconsistencias de flags y subcomandos entre `alera` y `alera orchestration` | Baja | Ergonomía CLI |
| 10 | El `workspaceId` no se descubre de forma directa | Baja | Ergonomía CLI |
| 11 | Versiones/commits reportados como `unknown` dificultan diagnóstico | Baja | Diagnóstico |

## 1. La detección de readiness no reconoce el TUI de Codex

`alera orchestration agent-spawn --agent codex ...` devolvió `{"outcome":"timeout","waitedMs":90000}`. El terminal creado quedó con `agentState: null` y `agentType: null` en `terminal-list`, aunque el proceso de Codex sí estaba vivo y mostrando su banner "OpenAI Codex (v0.145.0)". La tarea volvió a `ready` con `startup_failure_count: 1` y `result: "agent readiness timeout"`.

Causa probable: el detector de presencia de agente no matchea la interfaz de Codex v0.145.0. Además, el TUI tarda en arrancar ("Booting MCP servers...") más que parte de la ventana, lo que agrava el problema.

Impacto: el flujo automático de delegación a Codex no es utilizable; siempre cae en timeout.

Propuesta:

- Actualizar/ampliar las firmas de detección para Codex v0.145.x (banner, título de ventana `]0;… alera`, prompt `›`).
- Hacer la detección tolerante al arranque diferido: reintentar la detección durante toda la ventana en vez de decidir temprano.
- Exponer `--readiness-timeout-ms` en `agent-spawn` para entornos con TUIs lentos.

## 2. El único camino que funciona con Codex es el dispatch manual

Cuando la detección falla, ninguna ruta "automática" sirve:

- `agent-spawn --terminal <handle>` (reutilizar el terminal vivo) → `no agent detected in terminal <handle>; use --dry-run and paste the preamble manually`.
- `dispatch --inject` → también exige "a running agent" detectado.

La única secuencia que funcionó fue:

1. `dispatch --task <id> --to <handle>` (sin `--inject`): instala el contexto y deja la tarea en `dispatched` / `awaiting_acceptance`.
2. Escribir un prompt de arranque en el TUI que instruya al worker a correr `dispatch-accept` y `--json context`.
3. Enviar un Enter por separado (ver punto 3).

Impacto: el operador tiene que conocer un camino no documentado en la guía de la skill (que asume `agent-spawn` como flujo feliz).

Propuesta:

- Documentar el flujo manual de fallback en la skill/README de orquestación.
- Permitir `dispatch --inject` con un `--assume-ready`/`--skip-detection` explícito para desbloquear cuando el operador confirma que el agente está vivo.

## 3. `terminal write --enter` no somete el prompt en el TUI de Codex

Al escribir el prompt de arranque con `alera terminal write --handle <h> --text '…' --enter`, el texto quedó completo en el composer de Codex pero **no se envió**. El dispatch siguió en `awaiting_acceptance` durante más de 60s. Solo tras enviar un carriage return aparte (`alera terminal write --handle <h> --text $'\r'`) Codex sometió el prompt, corrió `dispatch-accept` y empezó a trabajar (`accepted_at` se rellenó).

Impacto: `--enter` es engañoso; sugiere que somete la entrada pero no lo hace en este TUI, y no hay señal de por qué la aceptación no llega.

Propuesta:

- Alinear el comportamiento de `--enter` con lo que el TUI destino espera (CR vs LF, o bracketed-paste seguido de CR), o documentar que en TUIs hace falta un envío de Enter separado.
- Considerar un modo `--submit` específico para TUIs interactivos que garantice el envío.

## 4. Intentos fallidos de spawn dejan terminales huérfanos

Tras el `agent-spawn` con timeout y reintentos, `terminal-list` mostró varios terminales colgando: un `zsh` vacío (starship), el Codex real, y dos terminales `running: false` sin agente. Ninguno se limpió automáticamente al fallar la readiness.

Impacto: el workspace se llena de terminales muertos que el operador debe cerrar a mano.

Propuesta:

- Al fallar la readiness, cerrar (o marcar para GC) el terminal que `agent-spawn` creó, salvo `--keep-on-failure`.
- Añadir un `terminal-prune` que cierre terminales sin agente ni dispatch.

## 5. Mensaje de error apunta a un flag inexistente en ese comando

`agent-spawn --terminal` falló con: `... use --dry-run and paste the preamble manually`. Pero `agent-spawn` no tiene `--dry-run`; ese flag vive en `dispatch`. El operador que sigue el mensaje literalmente choca con "unexpected argument".

Impacto: guía al usuario por un camino que no existe en el comando que está usando.

Propuesta: corregir el mensaje para nombrar el comando correcto, por ejemplo: `run 'alera orchestration dispatch --task <id> --to <handle> --dry-run --return-preamble' y entrégalo manualmente`.

## 6. No hay forma de esperar la finalización sin polling manual

Para saber cuándo Codex terminó tuve que hacer polling de `task-show` en un bucle propio. No existe un `terminal-wait --for completed` ni un `task-wait`. `check --wait` cubre `escalation,decision_gate` pero no la transición a `completed`.

Impacto: el coordinador tiene que implementar su propio sondeo; no hay una espera bloqueante nativa para el resultado.

Propuesta: añadir `task-wait --id <id> --for completed|failed|stalled --timeout-ms` (o extender `terminal-wait`/`check --wait` con esos tipos) para bloquear del lado del servidor.

## 7. `terminal-wait --for dispatch-accepted` da timeout aunque la aceptación ocurre

`terminal-wait --terminal <h> --for dispatch-accepted --timeout-ms 60000` devolvió `{"outcome":"timeout"}`, pero segundos después `task-show` mostraba `accepted_at` ya poblado. La condición de espera no reflejó el estado real.

Impacto: la espera no es confiable; puede reportar timeout cuando el evento sí ocurrió (probablemente ligado a que la aceptación depende de la detección de agente rota del punto 1).

Propuesta: basar `dispatch-accepted` en el estado del dispatch (`accepted_at != null`) y no en la detección de agente; revisar la condición de disparo del wait.

## 8. El preámbulo no es práctico para pegar en un TUI

`dispatch --dry-run --return-preamble` produjo un preámbulo de 5451 caracteres multilínea. Pegarlo crudo en un TUI es frágil: los saltos de línea pueden interpretarse como envíos por línea y no hay bracketed-paste garantizado. El workaround fue escribir un bootstrap corto que instruye al worker a leer el contexto vía `alera orchestration --json context`.

Impacto: la entrega manual del preámbulo es propensa a errores en agentes interactivos.

Propuesta:

- Ofrecer una entrega "por referencia": un prompt corto estándar que apunte a `context` (que el propio worker resuelve), en vez de volcar 5 KB al TUI.
- Si se pega el preámbulo completo, envolverlo en bracketed-paste al escribir en el terminal.

## 9. Inconsistencias de flags y subcomandos

- `alera terminal-show ...` → `unrecognized subcommand 'terminal-show'`, pero `alera orchestration terminal-show` sí existe. El mismo nombre vive en un solo nivel.
- `task-create` acepta `--workspace`, pero `terminal-list` lo rechaza (`unexpected argument '--workspace'`), aunque conceptualmente los terminales pertenecen a un workspace.

Impacto: fricción y prueba/error para descubrir la forma correcta de cada comando.

Propuesta: unificar convenciones de flags (todo lo que tenga alcance de workspace acepta `--workspace`) y ofrecer alias o mensajes de "quizás quisiste `alera orchestration <cmd>`".

## 10. El `workspaceId` no se descubre de forma directa

Para orquestar hace falta el `workspaceId`, pero no hay un comando directo que lo dé. Tuve que sacarlo de `alera orchestration --json terminal-show --handle $ALERA_TERMINAL_HANDLE` (campo `workspaceId`).

Impacto: paso extra no obvio antes de poder crear tareas o correr un coordinador.

Propuesta: exponer el `workspaceId` del terminal actual en `alera orchestration --json context` (o en `worker-help`/una variable de entorno tipo `ALERA_WORKSPACE_ID`).

## 11. Versiones y commits como `unknown`

`alera version --json` reporta `cliCommit: "unknown"` y `runtimeHostCommit: "unknown"`, y ambas versiones como `0.1.0`. Al diagnosticar incompatibilidades (como la detección de Codex) no hay forma de anclar a un commit concreto.

Impacto: dificulta reproducir y correlacionar bugs con builds específicos.

Propuesta: inyectar el commit real en build (por ejemplo vía `git describe`) para CLI y runtime-host.

## Nota de contexto

Pese a todo lo anterior, la tarea delegada se completó correctamente una vez aplicado el flujo manual: el worker aceptó el dispatch, implementó los cambios, corrió la verificación (`flutter test` 90/90, `flutter analyze` sin issues, `check_max_lines.dart`) y llamó a `complete` con `completionKind: success`. Los problemas de este documento son de ergonomía y fiabilidad del arnés de orquestación, no del resultado del trabajo.

## Resolución implementada

| # | Resolución |
| - | - |
| 1 | Codex ya no depende de un hook previo al primer turno. El host crea el dispatch, instala el contexto y arranca `codex` con un bootstrap corto como argumento posicional. |
| 2 | El fallback manual está documentado y `dispatch --inject --assume-agent <tipo>` permite un bypass explícito y auditado cuando el operador confirma el agente. |
| 3 | `terminal write --enter` separa la escritura y el carriage return. `--submit` usa bracketed paste y Enter diferido. |
| 4 | Un timeout limpia solamente el terminal creado por ese `agent-spawn`; `--keep-on-failure` lo conserva y `terminal prune` ofrece dry-run y `--apply`. |
| 5 | El error ya apunta al fallback real: dispatch sin inyección o `--assume-agent`. |
| 6 | `task-wait --task ... --for ...` espera cambios de estado dentro del runtime host. |
| 7 | `terminal-wait` también se resuelve en el host y hace una comprobación durable final al vencer el plazo. |
| 8 | Dispatch devuelve el bootstrap corto por defecto. El preámbulo completo solo se incluye con `--return-preamble` o `--dry-run`. |
| 9 | `alera terminal list/show/wait/prune` son comandos canónicos; se mantienen los nombres bajo `orchestration` por compatibilidad. |
| 10 | `ALERA_WORKSPACE_ID` es el default de los comandos con alcance de workspace y `alera orchestration current` muestra la identidad activa. |
| 11 | El build script incrusta `ALERA_BUILD_COMMIT` o resuelve el commit Git actual; `alera version --json` reporta esa procedencia. |
