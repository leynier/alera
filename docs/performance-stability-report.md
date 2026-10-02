# Reporte de auditoría de performance y estabilidad

## Resultado

La [segunda revisión](performance-stability-second-review.md), realizada sobre `1457a1072`, encontró cinco problemas prioritarios y mejoras adicionales. Las reparaciones posteriores del PR #888 corrigen tres de esos cinco problemas: cierre de hooks, pérdida de completions del runtime y procesos AI vivos tras salida inválida. El ACK de PTY y la clave del rate limiter de edge siguen pendientes, junto con los hallazgos adicionales que no están incluidos en los siete hilos seleccionados. Las validaciones del alcance inicial conservan su snapshot y no prueban automáticamente estas reparaciones posteriores.

El usuario añadió después la implementación de modelos dinámicos, thinking effort y Normal/Fast para Sign-in with ChatGPT, guardada en el commit local `2e61577f6`. Ese alcance y su validación se documentan en [ChatGPT AI Assist](chatgpt-ai-assist.md#model-catalog-thinking-effort-and-speed-follow-up) y en [la evidencia de validación](audit-chatgpt-options-validation-2026-10-02.json). El build Windows y las suites completas reportados abajo corresponden a la fuente previa `3958cef7d`; no verifican esta ampliación posterior.

Se auditó el cliente Flutter de escritorio, el runtime Rust, el cliente móvil, el backend cloud, el relay edge y el landing site.

Se implementaron correcciones locales para eliminar trabajo duplicado, acotar colas y streams, cancelar trabajo obsoleto, serializar transiciones de ciclo de vida y evitar fugas de recursos.

Los cambios están en la rama `perf/performance-stability-audit-release` del [PR #888](https://github.com/leynier/alera/pull/888). El usuario autorizó posteriormente subir las reparaciones de siete hilos de revisión y resolverlos después del push. Se mantiene la exclusión de merge manual, despliegue, publicación, creación de release y modificación de secretos o configuración externa; el runtime watch controla el merge cuando sea elegible.

La rama es `perf/performance-stability-audit-release`, basada en `b32c1492d` (v0.99.0). El alcance inicial está organizado en seis commits locales; el updater ampliado y su validación CI están en `a4c540de4` y `13971116e`, y la captura nativa de procesos en `bcce04666`. El runtime ampliado está en `b35966c88`, la admisión compatible bajo presión en `fbb360f5e` y el fixture de checkpoint asíncrono en `cf8045175`. La conservación de identidad durante el retiro remoto está en `ab7ed92cb`; el reporte de pestañas cerradas después de persistir está en `3958cef7d`. El fixture relay fija el workspace Rust en `92b807243`. El reporte se conserva junto al código para su revisión.

Las suites locales integradas del alcance inicial de desktop, Rust, mobile, cloud, edge y landing terminaron correctamente. La suite ampliada de desktop pasa 4,156 pruebas. La captura nativa de procesos, el updater y los límites de comandos/historial están implementados y validados. La suite final de Rust pasa 2,860 pruebas en 25 suites. El build debug de Windows con la fuente final termina con exit 0 y sus 526 archivos verificados coinciden por SHA-256; la recuperación desktop/móvil y los escenarios relay pasan con el código final. En macOS pasan tres pruebas VM del updater con procesos simulados; la app nativa no se compiló ni ejecutó.

El retiro remoto conserva la identidad local del proceso desde antes de cerrar al owner hasta la verificación final. Se reprodujo el fallo anterior con una demora artificial de 100 ms entre recoger el proceso y notificar su salida; la corrección pasa ese caso, tres retiros completos y la transferencia de identidad durante reintentos de historial. Esa instrumentación temporal se retiró del código.

Los contratos de protocolo existentes se conservan. El alcance ampliado añade una API nativa de captura de procesos con presupuesto; sus bindings se regeneraron con FRB 2.13.0. La dependencia local del updater añade parámetros públicos opcionales compatibles con sus llamadas anteriores.

Las mediciones de rendimiento se reportan solo cuando comparan entradas equivalentes y conservan la salida observable.

La evidencia de producción se consultó en modo lectura durante el diagnóstico, pero ningún cambio de esta auditoría se activó en servicios externos.

## Impacto en la experiencia de usuario

Estos efectos corresponden a los cambios locales; aún no están activos en producción.

1. Cambiar de workspace y refrescar archivos evita aplicar resultados obsoletos y trabajo duplicado. El editor reduce reconstrucciones innecesarias y protege conflictos de autosave.
2. Terminales y procesos aplican límites de memoria y esperan capacidad bajo presión. El historial aceptado conserva su orden; el cierre correcto espera su persistencia y muestra fallos en lugar de dar por completada una escritura pendiente.
3. Descargar, extraer y cancelar actualizaciones deja el trabajo pesado fuera del isolate de UI y limpia los recursos propios. Los diagnósticos comprimen en segundo plano; no se midió una mejora global de FPS.
4. En móvil, el cálculo sintético de atención de 1,024 workspaces es aproximadamente 50 veces más rápido conservando la salida. El backend inicia sin esperar los índices online y acota los envíos de notificaciones; su recepción sigue siendo best effort.
5. Sign-in with ChatGPT recupera el catálogo al quedar lista la cuenta y mantiene visibles los errores de refresco. Permite seleccionar el effort global o por operación y solicitar Normal/Fast. Los modelos y la disponibilidad de Fast dependen de lo que OpenAI habilite para la cuenta; no se inventa una lista fija ni se cambia silenciosamente la elección.

## Reparaciones de revisión del PR #888

El alcance solicitado parte del head `ba192b1b0` y cubre los siete hilos seleccionados. La implementación mantiene la identidad de las respuestas, el orden de admisión aceptado y la compatibilidad de las APIs existentes. Los hilos solo se resuelven después de confirmar el push de sus fixes.

| Área | Reparación | Regresión y validación |
| --- | --- | --- |
| Hooks | Detener el productor nativo antes de cancelar la suscripción FRB, preservando el primer error de cleanup y la serialización de start/stop. | 11 pruebas pasan. El test con cancelación realmente bloqueada falla con el orden anterior y pasa con el fix. |
| Procesos AI | Matar el árbol, cancelar ambos lectores y esperar la salida ante UTF-8 inválido, error de stream o exceso de salida, antes de propagar el error original. | 72 pruebas AI pasan, incluidas regresiones con hijo vivo y stdout/stderr abiertos; análisis enfocado sin incidencias. |
| Runtime y voz | Lane de completions de 128 mensajes y presupuesto ordinario de 16 MiB, independiente del control normal; productores esperan capacidad incluso tras cerrar la admisión de trabajo nuevo. PCM, turnos y síntesis consumen su presupuesto, con respuestas excesivas convertidas en errores. La metadata imprescindible de una operación ya comprometida se conserva y, si supera el presupuesto, se admite como único elemento en cola hasta retirarlo del inbox. | 42 pruebas enfocadas pasan, incluidos counter/client response, cleanup/ownership, guards, timers, ticker y fixtures de retiro/reinicio. El script completo de CI pasa 2,894 pruebas con 5 omisiones opt-in en 27 suites; Clippy del workspace pasa con warnings como errores. |
| Cloud push | Claims frescos en curso devuelven 503 reintentable. Fallos de persistencia liberan el lease como `retryable` cuando es posible. La reserva y sus contadores quedan en la misma transacción y no se repiten al reclamar un intento. | 22 pruebas unitarias y 5 contratos con PostgreSQL pasan, incluidos crash/reclaim, reintento inmediato, concurrencia y migraciones; formato y Clippy con warnings como errores aprobados. |
| Updater local | Cancelación inmediata y entre chunks; espera de cleanup, eliminación del parcial, preservación del destino anterior y reutilización de la siguiente descarga. HTTP conserva la finalización de cancelación previa sin esperar un body que no cierre. | 450 pruebas del paquete pasan y 10 quedan omitidas por entorno. El analyzer de CI termina con 0 errores y 376 infos existentes. El chequeo posterior al rename define el punto de commit del artefacto. |

El audio realtime usa la lane de trabajo de 64 MiB y conserva el descarte de frames cuando esa lane se satura. Las completions de trabajos admitidos esperan capacidad hasta su entrega o el cierre real del receptor. Los timers de Enter diferido y pulses también conservan su entrega; el ticker de recursos reintenta después de presión transitoria.

El análisis completo de Flutter, la conformance de spawns, el formato Dart y el ratchet de tamaño pasan. No hay cambios de superficies generadas ni de la API FRB que requieran regeneración. La validación usa fixtures locales, procesos simulados, sidecars/PTYs de prueba y PostgreSQL aislado; no hubo OAuth/inferencia ChatGPT, envíos reales FCM ni activación de la migración en producción.

El snapshot de validación anterior corresponde a `9107fb400`, que incluye los fixes de hooks `2606d31d5`, procesos AI `bf22bd662`, push/quota `7911aa6bc`, updater `d07b14ffe` y fixtures de historia `31fc8358c`. Los fixtures conservan las aserciones de reemplazo, vecino y ausencia de workers duplicados; ahora esperan la barrera durable y procesan la notificación legítima de historia. Rust usa el toolchain fijado 1.98.0 con todas las variables heredadas `ALERA_*` excluidas. Las 42 pruebas enfocadas son un subconjunto de la suite completa y no se suman de nuevo. El mapeo de los siete hilos a sus commits, comandos, resultados y límites está en [la evidencia de validación](audit-pr888-review-validation-2026-10-02.json), capturada antes del push.

La revisión adicional del hilo `PRRT_kwDORUczx86obHKC`, sobre `f87fb0534`, corrige el aviso compartido de capacidad: cada liberación despierta a todos los productores asíncronos y bloqueantes, porque Control, Work y Completion tienen predicados distintos. Esto evita que una finalización y su respuesta o contador queden esperando indefinidamente aunque su lane ya tenga espacio. Se conservan los presupuestos y el orden de los comandos aceptados.

Las dos nuevas regresiones llenan las tres lanes, registran primero productores de clases que siguen sin espacio y retiran únicamente el último Completion encolado. Ambas fallan con la implementación anterior y pasan con el fix; los 37 tests del inbox pasan, junto con Clippy del workspace con warnings como errores, rustfmt, whitespace y el ratchet de tamaño. La regresión asíncrona determina el orden de registro; reproducir el fallo anterior con Condvar depende de la selección del waiter por el sistema operativo, mientras que el fix despierta a todos en cualquier plataforma. Esta validación enfocada complementa el snapshot completo anterior; no se afirma una nueva ejecución de toda la suite Rust ni un build multiplataforma.

## Mejoras implementadas

| Área | Mejoras principales | Evidencia y estado |
| --- | --- | --- |
| Mobile | Recuperación de mensajes WebSocket malformados y construcción indexada de atención por workspace y agente. | 836 pruebas móviles, 4 casos de fixture cubiertos aparte y 6 ejecuciones adicionales de recovery y relay. Se repitieron con la fuente final y el sidecar nuevo. Completo. |
| Mobile benchmark | El cálculo sintético a 1,024 workspaces y 4,096 agentes bajó de 24,965 a 497 microsegundos de mediana. | Dos calentamientos, cinco muestras alternadas, igualdad y checksum. Es una comparación de algoritmos, no una latencia garantizada de teléfono. |
| Snapshots | Lectura inicial y eventos single flight, coalescing de refresh, cancelación de retries obsoletos y silencio después de cancelar. | 14 pruebas focalizadas; la fuente original reproduce 4 regresiones y aumenta lecturas simuladas de 1 o 2 a 14 o 15 por minuto. Completo. |
| Desktop explorer | Guardas por generación y por proyección nativa, descarte de resultados tardíos, watcher serializado y eventos coalescidos. | Casos para 100 eventos, resultados fuera de orden y cambio de workspace durante stop. Suite integrada aprobada. |
| Desktop editor | Rebuild del chrome solo al cambiar clean/dirty y bloqueo de save/discard durante conflictos de autosave. | Dos regresiones pasan con el editor nativo real en Linux/Xvfb, con limpieza de widgets. El código de las pruebas está integrado al workflow de build de las tres plataformas; la ejecución confirmada es Linux. |
| Process runner | stdin acotado, chunks de 256 KiB, cola Dart de 8 MiB y 64 escrituras, cola Rust de 32 elementos y 4 MiB, errores visibles y kill/reap ante overflow o fallo. | 11 casos de integración nativa pasan; suite Rust completa y Clippy aprobados. Eventos tardíos tras cierre no generan errores de controladores cerrados. |
| Captura general de procesos | Presupuesto combinado de stdout/stderr de 16 MiB; límites locales explícitos de hasta 64 MiB y deadline opcional. Cancelación termina el árbol, recoge al hijo y cancela lectores. En Windows el hijo se crea suspendido, se asigna al Job Object y después se reanuda. | Core Linux 11/11, facade 11/11 y Flutter nativo Linux 16/16; Windows ejecuta 4 casos con cmd real, overflow, timeout y limpieza. Revisión independiente cerrada. El host remoto actualizado comparte el collector; su suite integrada pasa con el runtime final. |
| Comandos e historial del runtime | Admisión acotada, writes FIFO idempotentes, checkpoints fuera del actor y cierre tras persistir. Audio válido de 25 MiB usa trabajo; lectores esperan capacidad sin desconectar. El retiro remoto conserva la identidad del proceso y reporta pestañas cerradas después de completar. | Completo: 2,860 pruebas Rust pasan, 5 skips optativos y Clippy con warnings como errores. Las regresiones de arranque, cierre, futuro de despacho, checkpoint y retiro remoto se corrigieron conservando sus aserciones y verificaciones. |
| Hooks y ConPTY | Cola de hooks de 256 eventos, retries limitados para 429/503, stop/start serializado y canal ConPTY acotado a 16 eventos. | Receiver, instalador y workspace completo aprobados. Las operaciones bloqueantes de archivos tienen cuatro permisos compartidos. |
| AI, proxy y Codex | Salida combinada limitada a 4 MiB en AI y 1 MiB en proxy, UTF-8 incremental, limpieza ante errores y cache de quota con generación. Transcripts Codex acotados y polling pausado en segundo plano. | Suite integrada y análisis aprobados. Lecturas de un watcher reemplazado no emiten estados obsoletos; recrear el transcript reinicia cursor y decoder. |
| Sign-in with ChatGPT | Refresco del catálogo dinámico, metadatos de reasoning por modelo, effort global y por operación, Normal/Fast explícito, conservación de settings al migrar y compatibilidad con runtimes antiguos. La ruta local sin caché de modelos conserva el effort; el gating remoto también cubre limpieza de texto de voz. | 248 pruebas Flutter y 41 Rust pasan; análisis, Clippy con warnings como errores, formato y ratchet aprobados. Sin inferencia real ni consumo de cuota; aceptación real con cuenta y build multiplataforma de esta ampliación pendientes. |
| Logging y diagnósticos | Campos de logs limitados a 8,192 unidades UTF-16 antes de redacción/JSON, sink con presupuesto de 256 KiB, flush de 64 KiB y descarte controlado bajo presión. | 21 pruebas de logs/redacción pasan; compresión del ZIP de diagnósticos en isolate y lectura asíncrona. Los campos excesivos se omiten completos para evitar exponer secretos. |
| Updater | Transporte HTTP con tamaño máximo firmado, timeout de cabeceras e inactividad, extracción ZIP en isolate cancelable e inyección del runner nativo y chmod por syscall. Limpieza DMG independiente de la cancelación y stages propios, conservando el error original. | Paquete local: 446 pruebas pasan y 10 skips por entorno; análisis con 0 errores y 376 infos bajo reglas upstream. App: 26 pruebas pasan; fixture VM macOS: 3 pasan con procesos simulados. Implementación y CI en commits locales; build Windows final aprobado. |
| Cloud push | Entrega FCM paralela con límite de 4, presupuesto de 12 segundos, quota y persistencia de intentos con recuperación de pendientes. | Reclaim atómico, UUID de lease renovado, finalización condicionada y lookup por cuenta verificados por revisión final. 22 pruebas Rust y 4 contratos PostgreSQL pasan. |
| Cloud schema | 16 índices online con `CREATE INDEX CONCURRENTLY` después de abrir el listener; esquema obligatorio validado antes de servir y consultas por cuenta. | Contratos verifican arranque con lock ocupado, rechazo de versión desconocida, reparación de índice interrumpido y conservación del checksum. EXPLAIN usa los índices; activación productiva no realizada. |
| Edge relay | Límite de 16 MiB/s por conexión, conserva la ventana durante renovación del grant y cierra con 1013 al excederla. | 38 pruebas Edge y TypeScript check pasan. Completo en local. |
| Landing | Demo limitada a 30 FPS, pausa fuera de viewport, dispose de listeners/observers, reduced motion dinámico e imágenes lazy con dimensiones. | 57 pruebas E2E, 103 unitarias, typecheck y build de 54 páginas pasan. |
| Landing release gate | Gate fail closed para releases GitHub y descriptores R2 estables, con timeout de cuerpo y semántica correcta de Vercel. | Gate y workflow preparados en source; sin activación externa. |
| Native lifecycle | Cleanup de servicios Linux, fallback de tray, balance de COM en Windows, detach de canales y guardas de mensajes tardíos. | 11 pruebas focalizadas y compilación Linux con Clang y G++ con `-Wall -Werror`. Build Windows final aprobado; activación GUI sin confirmar. macOS no compilado ni ejecutado. |

## Evidencia móvil

El benchmark está versionado en [audit-mobile-attention-2026-10-02.json](audit-mobile-attention-2026-10-02.json) y el ejecutable reproducible está en `mobile/tool/mobile_attention_benchmark.dart`.

La optimización evita escanear todos los agentes por cada workspace y conserva igualdad de salida, checksum y orden observable.

La suite móvil final de paquete pasó 836 pruebas con 4 skips existentes para fixtures que requieren sidecar o relay aislado.

La recuperación del sidecar, el relay normal y el relay con fallos se ejecutaron después con el binario nativo actual y pasaron en 6 ejecuciones adicionales.

## Estabilidad de entrega y límites conocidos

La entrega FCM ahora restringe concurrencia, reserva quota dentro del presupuesto y registra el resultado de cada intento para poder reclamar trabajo interrumpido.

La revisión independiente detectó y permitió corregir tres carreras: reclaim stale no atómico bajo dos consumidores, finalización de un lease antiguo sobre un lease nuevo y reutilización de eventos persistidos después de transferir un runtime entre cuentas. Ahora solo un consumidor reclama cada pendiente, un resultado tardío no puede sobrescribir el lease nuevo y el lookup incluye la cuenta. Tras una transferencia, repetir un identificador antiguo devuelve duplicado sin entregas ni contenido de la cuenta anterior.

Las migraciones obligatorias 0001-0004 y 0021 se verifican antes de servir. La nueva 0021 registra la reserva de quota por intento de entrega; considera reservados los intentos históricos para evitar cobrarlos de nuevo, y los nuevos requieren una reserva transaccional. Los 16 índices aditivos 0005-0020 se construyen en segundo plano, uno por uno, con espera de lock acotada a 30 segundos y presupuesto de 15 minutos por índice. Un build interrumpido se repara conservando el checksum original. Las versiones desconocidas se rechazan; un estado dirty requiere intervención operativa. Bajo CPU throttling, el lote online puede necesitar otro arranque o una fase operativa posterior, mientras el servicio continúa disponible con su esquema obligatorio.

Existe una ventana residual de duplicación si FCM confirma y el proceso cae antes de persistir el resultado. La entrega sigue siendo best effort, con reintentos acotados, y no garantiza exactly once ni la recepción de todas las notificaciones.

El relay conserva el límite existente de 1 MiB por frame y hasta ocho móviles, además del nuevo límite de ingress por segundo.

## Orden de publicación preparado

El gate del landing verifica que los tags fijados estén publicados, que los assets estén uploaded y tengan tamaño positivo, y que índice y descriptores R2 coincidan en versión, plataforma y build.

El workflow separa la publicación estable de GitHub/R2 del disparo posterior de Vercel y conserva el comportamiento de preview y builds locales.

El script de hook evita exponer el URL en argumentos de proceso, usa archivo temporal con modo 0600 y aplica timeout y retries acotados.

No se creó `VERCEL_PRODUCTION_DEPLOY_HOOK`, no se agregó ningún secret y no se ejecutó el hook.

La evidencia final del runtime está versionada en [audit-runtime-validation-2026-10-02.json](audit-runtime-validation-2026-10-02.json). La verificación del build Windows y los hashes de la app y del sidecar están en [audit-windows-validation-2026-10-02.json](audit-windows-validation-2026-10-02.json).

## Validación consolidada

| Validación | Resultado |
| --- | --- |
| Mobile codegen, normalize, format y analyze | Completados con Flutter 3.47.2 y Dart 3.13.2. |
| Mobile tests y fixtures recovery/relay | 836 pass, 4 skips existentes y 6 ejecuciones de fixtures pass con la fuente final. Recovery desktop y móvil usan un sidecar recién compilado con versión isolated-test. |
| Snapshot stream | 14 pass. |
| Landing unit, typecheck y build | 103 unitarias, typecheck y 54 páginas pass. |
| Landing Playwright | 57 casos pass con las combinaciones de rutas, viewport y accessibility. |
| Cloud y PostgreSQL | 22 Rust y 4 contratos aislados pass; Clippy, formato, arranque y reparación de índices validados. |
| Edge relay | 38 pass y TypeScript check pass. |
| Native Linux | 11 pruebas y compilación Clang/G++ con warnings como errores pass. |
| Rust integrado | 2,860 pass y 5 skips optativos en 25 suites; Clippy de todo el workspace con warnings como errores pasa. El fixture relay omitido se ejecutó por separado. |
| Desktop integrado | 4,133 pass en cuatro shards y 3 skips existentes. Generación, normalize, format, analyze y max-lines aprobados; 23 golden pass. |
| Desktop ampliado | 4,156 pass en cuatro manifests congelados, con 3 skips existentes. El shard afectado por una comprobación antigua del paquete hosted pasó tras corregirla para verificar el fork local 2.7.0. |
| Cobertura desktop | 100% de líneas del dominio mantenido, 4,975/4,975, combinando los cuatro artefactos finales. No representa cobertura de toda la plataforma. |
| Updater VM macOS | 3 casos pass en una fixture mínima aislada con fuentes verificadas por SHA-256; incluye cancelación del adaptador durante copia DMG, espera de salida, detach fallido y fallback forzado. Procesos simulados, sin build de app nativa ni herramientas de instalación reales. |
| Desktop nativo Linux | Editor 2/2, proceso 11/11 y recuperación del runtime 1/1 pass, con binarios actuales. |
| Windows native debug, fuente final | Build Flutter 3.47.2 aprobado con exit 0 en 20 minutos; 526 archivos de fuente coinciden por SHA-256 en el mirror aislado. App y sidecar compilados y sus hashes registrados. Sin instalación ni ejecución GUI. |
| CTest nativo Windows | El target Release compila. CTest falla: 7 aserciones sin GUI pasan y 5 de activación/restauración fallan en la sesión SSH 0, sin escritorio interactivo. |

Los tres skips de la suite desktop por defecto corresponden al fixture de recuperación, un caso específico de Windows y la disponibilidad de PowerShell 7. La recuperación se validó aparte; los dos casos específicos de Windows no se ejecutaron en Linux. Los cinco skips Rust son verificaciones opt-in de servicios o fixtures; el relay se ejecutó aparte. No se redujeron aserciones ni reglas de accesibilidad para aprobar las suites.

## Riesgos y trabajo pendiente

El inbox acotado y el writer serial de historial retienen los lotes aceptados en orden y pausan el productor ante saturación o error de almacenamiento. Las reparaciones de revisión y las regresiones de compatibilidad están validadas en la suite final. El cierre espera la persistencia sin bloquear el actor; los requests repetidos no multiplican timers ni trabajos. Un fallo permanente del almacenamiento deja el cierre pendiente y conserva los datos aceptados. Un apagado forzado o pérdida de energía aún puede perder bytes que no han llegado al almacenamiento.

La captura general de procesos locales y remotos usa un presupuesto combinado de 16 MiB por defecto. La captura local permite límites explícitos de hasta 64 MiB y deadline opcional; conserva la ausencia de timeout por defecto para comandos locales largos. El host remoto actualizado mantiene 16 MiB y su timeout configurado, y rechaza overrides no soportados; un host antiguo necesita incorporar estos cambios para aplicar el nuevo límite de captura. La terminación de descendientes y la recolección del hijo se validaron en Linux y Windows. La suite integrada del host remoto ampliado pasa.

La dependencia local `desktop_updater` 2.7.0 ya tiene extracción ZIP en un worker isolate, cancelación con espera de su salida y runners inyectados para operaciones y limpieza. La app usa su runner nativo y chmod por syscall. Las 446 pruebas del paquete y las 26 de integración de la app pasan; tres casos de la fixture VM macOS pasan por separado. Diez casos del paquete requieren otro entorno: tres E2E de publicación con credenciales y siete específicos de macOS; no se ejecutaron E2E de publicación externa. El analyzer del vendor termina con 0 errores y 376 infos de sus reglas upstream, sin modernizar su código. Los barridos de stages obsoletos, el hash y el análisis de metadatos PKG conservan una cancelación cooperativa. El decoder puede consumir memoria proporcional al archivo dentro del worker. Los symlinks internos de bundles macOS se manejan mediante `ditto` sobre artefactos firmados. Los artefactos `file:` omiten el límite HTTP, pero usan la misma extracción aislada. El runner por defecto del paquete no cancela procesos activos; la ruta Alera inyecta su adaptador cancelable.

El límite de los logs se aplica a cadenas ya disponibles; un `Object.toString()` personalizado todavía puede ejecutar trabajo arbitrario antes de devolver una cadena.

Los índices cloud se construyen en segundo plano y pueden requerir reintento posterior bajo restricciones de CPU o locks prolongados; su finalización debe verificarse durante una futura activación.

La compilación debug Windows con el código final terminó correctamente el 2 de octubre de 2026. Los 526 archivos verificados coinciden por SHA-256 con el mirror aislado; la app y el sidecar tienen hashes registrados. Esta evidencia cubre el alcance ampliado y no implica validación GUI. El target nativo CTest compiló, pero su ejecución por SSH no valida activación de ventanas: un diagnóstico aislado confirmó `OpenInputDesktop` con `ERROR_INVALID_FUNCTION (1)` y ventanas creadas que permanecen invisibles (`IsWindowVisible=0`) en la sesión 0. Los cinco fallos se conservan como una limitación de ejecución; no se modificó el test para convertirlos en pass. La validación GUI de Windows y el build/runtime macOS no están confirmados.

El Mac tiene Xcode y el SDK Flutter, pero falta CocoaPods para compilar la app. El [skill build-on-macos](/home/leynier/.agents/skills/build-on-macos/SKILL.md) indica: "If CocoaPods is unavailable while the project requires `Pods/`, stop and report the missing prerequisite before installing tooling or syncing generated dependencies." Por ello se dejó explícita esa limitación y se ejecutó la fixture VM del updater, que no requiere Pods. No se instalaron herramientas globales.

No hay evidencia de producción para estos cambios porque el despliegue y la publicación fueron cancelados por el usuario.

La activación futura requiere una nueva instrucción del usuario que autorice el despliegue o la publicación, ejecutar los checks remotos del commit elegido y comprobar la finalización de índices en el entorno de destino. El hook externo y su secret siguen sin configurar. Las pruebas nativas de macOS y la activación GUI de Windows requieren sus respectivos entornos interactivos.

El detalle operativo y el estado de tareas se mantiene en [performance-stability-audit.md](performance-stability-audit.md).
