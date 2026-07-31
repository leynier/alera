# Contexto del POC de Alera con GPUI

## Propósito

Esta conversación evaluó y finalmente implementó un POC para determinar si Alera Desktop puede reimplementarse con GPUI, reutilizando el runtime-host de Rust existente y manteniendo temporalmente el cliente Flutter. El objetivo no fue producir un reemplazo listo para distribución, sino eliminar las principales dudas de arquitectura, integración y rendimiento mediante una implementación ejecutable y medible.

## Evolución de la conversación

La solicitud inicial fue analizar la factibilidad de GPUI para Alera, revisar cada área funcional, identificar crates útiles y estudiar el código abierto de Zed, cuyos creadores mantienen GPUI. Después se discutieron las implicaciones generales de la licencia de Zed y la diferencia entre MIT y GPL.

La conclusión preliminar sobre licencias fue que MIT permite reutilización con pocas obligaciones, mientras GPL exige que las obras derivadas distribuidas mantengan el copyleft. También se reconoció que Alera podría seguir siendo Open Source bajo una licencia compatible si en el futuro reutilizara código sujeto a copyleft. El usuario decidió aplazar el análisis legal detallado porque esta fase era únicamente un POC. Por ello, la implementación no importa crates de producto de Zed ni copia su terminal. Una fase de producción todavía debe auditar por crate, archivo, dependencia y procedencia cualquier reutilización.

El usuario excluyó inicialmente updater y browser. El alcance se definió de forma interactiva, acompañando cada área con su complejidad y permitiendo decidir qué incluir. También se exigió que la implementación completa se realizara bajo un goal explícito.

## Goal ejecutado

Se creó y completó el siguiente goal:

> Implementar y validar el POC completo de Alera Desktop con GPUI definido en el plan acordado: cliente Linux Wayland/X11 aislado, coexistencia con Flutter sobre el mismo runtime-host, paridad seleccionada de shell/workbench/terminal/files/editor/Git/PR/AI/agentes/recursos/orquestación/settings/mobile devices/diagnostics, y gate final de rendimiento sin pérdida de datos.

El goal quedó marcado como completado después de implementar el alcance, ejecutar las pruebas y documentar la decisión de factibilidad.

## Alcance acordado

### Incluido

- Cliente GPUI específico para Alera, aislado bajo `experiments/alera-gpui`.
- Linux con Wayland como backend predeterminado y compilación alternativa para X11.
- Coexistencia de Flutter y GPUI contra el mismo runtime-host.
- Shell visual de Alera, activity rail, proyectos, workspaces, tabs, estado y conexión.
- Terminal real con PTY administrado por el runtime-host, binary frames, entrada, resize, scrollback, paste, título, detach y resync.
- Bakeoff entre `alacritty_terminal` y `libghostty-vt`.
- Explorer, búsqueda y replace-all.
- Editor con resaltado Tree-sitter, dirty state y guardado seguro.
- Preview de Markdown, Mermaid e imágenes.
- Estado, diff, historial y mutaciones Git.
- Pull requests, checks, comentarios y operaciones de GitHub mediante `gh`.
- AI Text mediante la identidad y el runtime existentes.
- Agentes, perfiles, presencia, cuotas, Resource Manager, Orchestration, settings, mobile devices y diagnostics.
- Confirmaciones explícitas para operaciones destructivas.
- Benchmarks comparativos de streaming, reposo, restauración e input.

### Excluido o aplazado

- Browser.
- Updater.
- PDF preview.
- Account y OAuth.
- SSH.
- LSP.
- Emulator embedding.
- macOS y Windows.
- Auditoría final de licencias.

## Diseño resultante

El POC mantiene al runtime-host como dueño de las sesiones, el catálogo y las operaciones persistentes. El cliente GPUI no abre `runtime.sqlite`.

Se extrajeron dos crates compartidos:

- `rust/alera-runtime-protocol`: constantes del protocolo, codec de frames de texto y binarios, y tipos compartidos.
- `rust/alera-runtime-client`: conexión autenticada, requests concurrentes correlacionados, eventos, handshake, persistencia y API de escritorio.

El cliente existente de `alera-cli` reexporta estas implementaciones para evitar una segunda versión del protocolo. La lógica GPUI vive separada en `experiments/alera-gpui`, por lo que no forma parte del build de distribución de Flutter.

El proceso GPUI usa un bridge de Tokio para comunicarse con el runtime-host y entrega cambios a entidades de GPUI. Las operaciones de archivos, búsqueda, previews y forge se ejecutan fuera del camino de render. Git reutiliza `alera_native`, y las llamadas a procesos externos conservan el boundary windowless de Alera.

## Implementación funcional

### Runtime y coexistencia

- Conexión al runtime-host instalado usando el runtime activo.
- Compatibilidad con framing legado por líneas y framing binario.
- Soporte para los dos órdenes de handshake observados.
- Requests concurrentes con correlación y timeouts.
- Eventos, reconexión y estado de conexión.
- Flutter y GPUI conectados simultáneamente al mismo host.
- Cerrar GPUI no detiene Flutter ni el runtime-host.

### Shell y workbench

- Tema oscuro inspirado en la estructura visual de Alera.
- Activity rail, sidebar, selector de proyecto y workspace.
- Tabs, estado de branch, conexión y superficies por actividad.
- Lectura de proyectos, workspaces, tabs y layout reales.
- El POC carga layout, pero aún no implementa split panes completos, drag and drop ni toda la gestión visual de tabs.

### Terminal

- Emulador basado en `alacritty_terminal` 0.26.
- Attach y create-or-attach contra sesiones reales.
- Snapshot, output binario, UTF-8 incremental y resync.
- Entrada de teclado, resize dinámico y bracketed paste.
- Scrollback, título y respuestas de control.
- Validación del marcador final después de restaurar 2.56 MB para detectar pérdida de datos.
- Sin timer o frame loop sostenido cuando no cambia el estado.

El bakeoff del parser usó el mismo corpus ANSI determinista de 2,560,000 bytes:

| Motor | Mediana | p95 | Throughput |
| --- | ---: | ---: | ---: |
| `alacritty_terminal` 0.26 | 122.753 ms | 240.455 ms | 20.85 MB/s |
| `libghostty-vt` | 68.059 ms | 68.153 ms | 37.61 MB/s |

`alacritty_terminal` se eligió para el POC por su API Rust directa y menor coste de integración. `libghostty-vt` quedó recomendado para una evaluación de producción porque fue 1.80 veces más rápido por mediana.

### Archivos, búsqueda, editor y previews

- Resolución y validación canónica de paths para impedir escapes del workspace.
- Explorer con carga lazy y trabajo de I/O fuera del render.
- Búsqueda de workspace y replace-all confirmado.
- Editor multiline con Tree-sitter mediante `gpui-component`.
- Dirty state y guardado protegido por token de contenido.
- Confirmación antes de sobrescribir un archivo cambiado externamente.
- Markdown renderizado de forma nativa.
- Mermaid convertido a SVG en memoria.
- Preview de imágenes locales.
- Toggle entre source y preview.

### Git, PR, CI y AI

- Git status, staged y unstaged files, branch, diff e historial.
- Stage, unstage y discard por path o global.
- Commit, amend, fetch, pull, push, stash y pop.
- Confirmaciones para mutaciones peligrosas.
- Integración interactiva de GitHub con el `gh` instalado, ejecutado por el boundary de procesos de Alera.
- Lectura del PR de la branch actual, checks, comentarios y reviews.
- Crear o actualizar PR, marcar draft o ready, comentar, cerrar y merge mediante merge, squash o rebase.
- GitLab y Azure no fueron implementados.
- AI Text usa `aiText.workspaceIdentity.generate`, timeout de 10 minutos y cancelación.

### Superficies operativas

Se añadieron cards con estado real y una consola de acciones allowlisted para:

- Agents, profiles, presence y quotas.
- Resource Manager.
- Orchestration protocol v2.
- Runtime, workbench y project settings.
- Mobile status, devices y runtime settings.
- Diagnostics, runtime status, CLI registration y shell environment reload.

Estas áreas demuestran integración real, pero parte de la UX sigue siendo JSON en lugar de formularios, tablas o visualizaciones tipadas.

## Investigación de Zed

Zed confirmó la viabilidad general de separar PTY, estado de terminal y render GPUI. También sirvió como referencia para arquitectura, patrones de GPUI y terminales derivados de Alacritty.

El POC no enlaza crates de producto de Zed ni copia su implementación de terminal. Las dependencias reutilizadas directamente son GPUI, `gpui-component`, `alacritty_terminal` y las capas existentes de Alera. Esto mantiene el experimento concentrado y evita acoplarlo al grafo completo de la aplicación Zed.

## Resultados de rendimiento

Todas las mediciones se realizaron en la misma sesión gráfica Linux el 30 de julio de 2026.

### Streaming

| Cliente | Entrada | Presentación | CPU |
| --- | ---: | ---: | ---: |
| Flutter | 89 writes/s | 29.0 flushes/s y 59.3 binding frames/s | 82.0% de un núcleo |
| GPUI release | 120.3 writes/s | 30.1 rendered frames/s | 14.5% de un núcleo |

GPUI utilizó 82.3% menos CPU mientras aceptaba 35.2% más writes por segundo. El gate exigía una reducción mínima de 30%.

### Reposo

GPUI produjo solamente 2 frames de startup durante 8.01 segundos y utilizó 1.12% de un núcleo. No quedó un frame loop activo.

### Restauración

| Cliente | Mediana | p95 |
| --- | ---: | ---: |
| Flutter | 1,351.24 ms | 1,377.26 ms |
| GPUI release | 25.10 ms | 29.13 ms |

GPUI fue 53.8 veces más rápido por mediana. Ambos benchmarks conservaron sus marcadores y assertions; el benchmark Flutter fue ajustado para drenar el backlog vivo después del intervalo medido y terminar limpiamente.

### Input

El microbenchmark reportó 0.010 µs p95 para Flutter y entre 0.028 y 0.078 µs p95 para GPUI. Ambos permanecen por debajo de un microsegundo. Esta prueba mide encoding y callbacks, no latencia física completa desde teclado hasta echo del PTY.

## Validación realizada

- `cargo clippy --manifest-path experiments/alera-gpui/Cargo.toml --all-targets -- -D warnings`.
- Tests de todos los targets del experimento.
- Compilación X11 con `--no-default-features --features x11`.
- Lanzamiento real en Wayland.
- Smoke live de 18 verbs del runtime.
- `make rust-test`, incluyendo fmt, Clippy y tests del workspace Rust.
- `cargo check --locked` para el workspace Rust y todos los targets del experimento.
- Benchmark de streaming de Flutter.
- Benchmark de input de Flutter.
- Benchmark de restore de Flutter.
- Modos stream, idle y restore del benchmark GPUI release.
- Bakeoff VT de Alacritty y Ghostty.
- Coexistencia simultánea de Flutter y GPUI.
- `dart format`, `cargo fmt`, `git diff --check`, verificación de ausencia de em dash y límite de 500 líneas por archivo.

`-D warnings` indica a Rust y Clippy que trate cada warning como un error. El POC pasó ese gate sin warnings.

Antes de publicar la rama también se ejecutó `gh act pull_request -W .github/workflows/pr.yml -j rust`. El checkout, setup, format y Clippy pasaron. Tres tests fallaron únicamente dentro del contenedor: dos porque el usuario `root` puede leer archivos con modo `000`, y uno por la propagación del entorno a un proceso envuelto por Docker. Las tres pruebas pasaron al reejecutarlas de forma nativa, y la suite nativa completa ya estaba verde. Los workflows de `push` no se ejecutaron localmente porque solo aplican a `main` e incluyen startup, calentamiento de cachés o despliegue cloud, no esta rama.

## Cómo ejecutar la aplicación

Desde la raíz del repositorio, Wayland en release:

```bash
cargo run --release --manifest-path experiments/alera-gpui/Cargo.toml --bin alera-gpui
```

Wayland en debug:

```bash
cargo run --manifest-path experiments/alera-gpui/Cargo.toml --bin alera-gpui
```

X11:

```bash
cargo run --release --manifest-path experiments/alera-gpui/Cargo.toml --no-default-features --features x11 --bin alera-gpui
```

El cliente lee `ALERA_RUNTIME_DIR` cuando existe y, de lo contrario, usa el runtime Alera predeterminado. Flutter puede permanecer abierto.

## Conclusión

La decisión del POC es `Go` para una migración gradual, no para reemplazar Flutter inmediatamente. La arquitectura, la conexión compartida al runtime, el terminal real y el rendimiento están demostrados. Los riesgos principales ya no son de viabilidad básica, sino de completar la experiencia de producto.

La siguiente fase debería priorizar selección y copy del terminal, IME, mouse modes, hyperlinks, search, protocolos modernos, split panes, accesibilidad, comandos y menús, typed operational screens, packaging Linux y pruebas reales en varios compositores. macOS, Windows y licencias deben tener gates propios antes de cualquier decisión de distribución.

## Documentación relacionada

- `experiments/alera-gpui/README.md`
- `experiments/alera-gpui/docs/implementation-plan.md`
- `experiments/alera-gpui/docs/architecture.md`
- `experiments/alera-gpui/docs/feature-matrix.md`
- `experiments/alera-gpui/docs/performance.md`
- `experiments/alera-gpui/docs/vt-bakeoff.md`
- `experiments/alera-gpui/docs/feasibility.md`

## Rama de publicación

Todos los cambios de este POC se prepararon en `docs/analyze-gpui-reimplementation-feasibility`, un workspace administrado por Alera creado desde `main`.
