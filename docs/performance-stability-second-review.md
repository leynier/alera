# Segundo informe de auditoría de performance y estabilidad

## Alcance y estado

Esta revisión es un análisis de solo lectura del HEAD `1457a1072`, con último commit de producción `3958cef7d` y base `b32c1492d6f2d82b127e1444979444cd1b58e03a`.

Las seis áreas de la segunda revisión terminaron su análisis y el revisor independiente dejó cinco hallazgos accionables de prioridad P1. También se ejecutaron probes locales sobre hook nativo, PTY, explorer, AI, updater, diagnósticos, edge, mobile y contratos de FCM.

No se editaron fuentes durante esta revisión, no se hicieron inferencias con los providers de la aplicación ni se consumió cuota ChatGPT del usuario, no se escribieron sistemas de producción y no se desplegó ni publicó ningún cambio. La revisión independiente de código sí utilizó el CLI Codex configurado, como registra la evidencia.

La evidencia completa de los probes está en [audit-second-review-evidence-2026-10-02.json](audit-second-review-evidence-2026-10-02.json).

Las conclusiones distinguen entre pruebas dinámicas aisladas, revisión estática y decisiones de contrato todavía abiertas. Un probe local no es evidencia de comportamiento en producción.

El usuario autorizó investigar e implementar las opciones SIWC en paralelo, con alcance separado. Este documento describe el HEAD revisado y no supone que el código vaya a quedar sin cambios después de esa investigación.

El seguimiento del [PR #888](https://github.com/leynier/alera/pull/888) implementa reparaciones posteriores para hooks, completions del runtime, procesos AI, contabilidad de voz, push retry/quota y cancelación local del updater. El estado y la validación actualizados están en [el reporte de implementación](performance-stability-report.md#reparaciones-de-revisión-del-pr-888); este documento conserva las observaciones y los probes del snapshot original, incluidos el ACK de PTY y el limiter edge que siguen pendientes.

## Cinco hallazgos P1

| Hallazgo | Evidencia | Fuente y regresión requerida | Impacto y cierre requerido |
| --- | --- | --- | --- |
| Stop de hook nativo puede bloquear cancelación | El probe marca `cancellationBeforeNativeStopCompleted=false` y `cancellationAfterNativeStopCompleted=true`. | [`agent_hook_receiver.dart:116`](../lib/src/features/agent_status/infra/agent_hook_receiver.dart:116). Regresión: iniciar sin eventos, llamar `stop()` y `dispose()` y comprobar que el productor se detiene antes de esperar `subscription.cancel`, y que ambas operaciones terminan en orden. | El lifecycle puede quedar esperando el stop nativo. El remedio raíz es detener el productor nativo antes del `await` de cancelación de la suscripción; un timeout solo limita el daño y no sustituye ese orden. |
| La inbox acotada puede perder completions y contadores de trabajos creados | Revisión estática del límite de admisión y de los mensajes internos emitidos por tareas spawned. No se hizo una medición dinámica equivalente. | [`server_command_inbox.rs:117`](../rust/alera-cli/src/terminal_host/server/server_command_inbox.rs:117), [`managed_workspace_requests.rs:48`](../rust/alera-cli/src/terminal_host/server/managed_workspace_requests.rs:48). Regresión: llenar la clase de trabajo, crear una tarea que deba publicar completion y contador, y comprobar que ningún resultado queda sin resolver ni se pierde durante overflow y shutdown. | Rechazar una orden de control o su completion puede dejar estado, contadores o promesas sin resolver. El overflow debe preservar completions, shutdown y contabilidad, aplicando backpressure a productores seguros. |
| ACK de PTY con pacing invertido | Un productor de 20 ms entregó bytes en 40, 141, 242, 260 y 337 ms. El probe muestra agrupación cercana a 100 ms. | [`server.rs:667`](../rust/alera-cli/src/terminal_host/server.rs:667), [`pty_events.rs:108`](../rust/alera-cli/src/terminal_host/server/pty_events.rs:108). Regresión: producir bytes cada 20 ms durante una ventana sostenida y verificar que el ACK no introduce una espera fija cercana a 100 ms ni invierte la ventana de backpressure. | La confirmación puede retrasar la salida visible y aumentar latencia interactiva. Hay que validar la dirección del ACK, la ventana y el límite bajo productor continuo. |
| AI no mata el hijo ante UTF-8 inválido | El runner público devuelve `FormatException` a los 6,001 ms; `killCalled=false` y `exitCompleted=false`. El fake público reproduce el caso. | [`ai_assist_agent_runner.dart:261`](../lib/src/features/ai_assist/application/ai_assist_agent_runner.dart:261). Regresión: emitir bytes UTF-8 inválidos mientras el hijo sigue vivo y comprobar kill, reap y cierre de streams antes de propagar la excepción. | El proceso puede seguir vivo después del error de decodificación. La ruta de error debe matar y esperar el árbol del proceso antes de propagar la excepción. |
| Rate limiter de edge permite rotar Authorization inválido | Con una IP fija y 11 Authorization falsos distintos, el origin recibió 11 llamadas y todas devolvieron 200. Con el mismo valor, las primeras 10 devolvieron 200 y la 11 devolvió 429. | [`index.ts:62`](../edge/src/index.ts:62). Regresión: repetir requests mutantes desde una IP fija con Authorization inválido rotatorio y comprobar que el límite se aplica antes de cada llamada al origin. | El bucket local usa una clave que cambia con el digest de autorización. Debe existir una identidad estable para entradas no autenticadas, sin convertir el token inválido en una identidad ilimitada. El resultado usa un origin fake local. |

Los cinco hallazgos anteriores son bloqueadores de estabilidad o control de abuso para el alcance ampliado. No se implementaron aquí y no se presentan como corregidos.

## Hallazgos de desktop y explorer

El probe de cambio de modo del Explorer creó un archivo después del toggle y no lo observó en el modo esperado. La evidencia proviene de dos probes widget aislados y requiere revisar la invalidación del watcher al cambiar `hideIgnored`.

El probe de proyección masiva cambió cinco directorios, ejecutó cinco proyecciones y produjo seis snapshots por proyección, con 30 entradas de payload. Esto evidencia trabajo repetido que puede crecer de forma cuadrática con directorios cargados y snapshots, aunque no es una medición de una sesión de producción.

Las guardas de generación ya existentes impiden varias respuestas tardías, pero no convierten por sí solas la construcción de cada proyección en una operación incremental. La optimización debe conservar orden, modo y estado Git observable.

## Hallazgos de AI y procesos

Cuando el proceso AI recibe una invocación sin payload, el runner público no cierra stdin: el fake termina en timeout de un segundo, con `stdinCloseCalls=0`, aunque el timeout sí solicita kill y espera la salida.

El mismo fake termina con `ok` cuando el harness llama `stdinClose`, por lo que el EOF es la condición que diferencia ambos resultados.

La prueba de UTF-8 inválido es independiente y más grave: la excepción aparece antes del timeout configurado, mientras el hijo continúa vivo seis segundos después de iniciarse el probe.

La ruta general de salida nativa drenó 2 MiB del pipe, pero el stream Dart retuvo los 2 MiB hasta que un listener se conectó después de la salida del proceso. Es evidencia de buffering sin consumidor, no una medición de RSS de la aplicación instalada.

La ruta de voz dejó 2 MiB de stdout y stderr sin consumir mientras esperaba `exitCode`; el listener tardío recuperó el buffer completo. El cierre de la sesión de voz debe consumir, descartar con presupuesto o cancelar ambos streams explícitamente.

## Hallazgos del updater

El probe de `file:` copia 16 MiB y solicita cancelación después de 65,536 bytes. El destino termina con los 16 MiB, la copia completa después de cancelación y 255 callbacks de progreso posteriores.

La cancelación HTTP no cubre automáticamente la ruta local `file:`. El contrato debe decidir si esa ruta cancela por chunks, marca el resultado como obsoleto y limpia el destino, o continúa hasta una frontera segura documentada.

El probe de cambios de modo ejecutó 512 directorios y 512 llamadas de mode sin observar ningún callback de `Timer.run` antes de completar. La función de archivos ya contiene un `Future.pause(Duration.zero)` cada 64 paths; este dato es una propiedad de implementación y no un conteo de 64 yields observados en el probe.

El resultado no demuestra que chmod sea incorrecto, pero sí que un lote grande puede monopolizar el event loop. [`applyUpdaterFileModes`](../lib/src/features/updater/infra/updater_process_adapter.dart:161) ya inserta el yield cada 64 paths. La corrección debe preservar permisos, symlinks, cleanup y cancelación, y debe medirse con un fixture de directorios suficientemente grande.

## Diagnósticos y uso de memoria

El benchmark AOT aislado procesó 50 MiB de logs sintéticos de alta entropía, produjo 43,583,206 bytes, tardó 1,104 ms y pasó de 11,624,448 a 179,040,256 bytes de RSS muestreado.

El delta observado fue 167,415,808 bytes, aproximadamente 159.7 MiB. Esta cifra es una señal de presión de memoria para el pipeline de bundle, no una medición de RSS del proceso Flutter completo.

El siguiente paso debe separar buffers, representación de strings, compresión y salida ZIP, además de repetir la medición con logs reales redacted y límites de tamaño. No se debe convertir este benchmark aislado en una afirmación de consumo de producción.

## Browser, mobile y contratos de transporte

El probe de BFCache simuló `pagehide persisted=true` y `pageshow persisted=true`; el player se destruyó, no se instaló un listener de remount y el DOM restaurado quedó sin player vivo. Es una simulación aislada del lifecycle de [`player.ts`](../landing/src/scripts/demo/player.ts), no una captura de Back real en un navegador ni un conteo de cleanup productivo.

La prueba mobile de RPC tiene tres casos pass: un timeout deja utilizable el transporte para solicitudes posteriores, y eventos desconocidos o respuestas numéricas tardías mantienen compatibilidad.

Los envelopes de protocolo inválidos son un hallazgo P2 confirmado: un JSON que no es mapa, o un objeto que no contiene ni un `event` string ni un `id` entero, debe fallar de inmediato y resolver los pendientes con error, sin cambiar la versión del protocolo. La implementación revisada todavía ignora esos casos en [`mobile_runtime_client.dart:416`](../mobile/lib/src/features/runtime/infra/mobile_runtime_client.dart:416); la regresión debe ampliar [`mobile_runtime_client_malformed_message_test.dart:9`](../mobile/test/mobile_runtime_client_malformed_message_test.dart:9).

El comportamiento de timeout del RPC es una decisión de contrato separada: conservarlo permite que una conexión siga utilizable y que un mensaje sin respuesta termine por timeout, mientras el cambio P2 se limita a envelopes estructuralmente inválidos.

## FCM y backend cloud

El análisis aritmético de payload toma 20 campos de evento, añade cinco campos confiables y serializa 21,863 bytes. No hubo llamadas de red ni envío real a FCM.

La evidencia de source confirma límites internos de 20 campos y 1,024 bytes por valor, pero no encontró guardia del tamaño serializado ni rechazo de nombres reservados. El campo reservado `from` sobrevive al mapa enviado al wire.

Firebase documenta un máximo de 4,096 bytes para la mayoría de los mensajes y prohíbe nombres reservados como `from`, `message_type` y prefijos `google.` o `gcm.` en data messages. Ver [message types](https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type), [error codes](https://firebase.google.com/docs/cloud-messaging/error-codes) y [FCM scale and retries](https://firebase.google.com/docs/cloud-messaging/scale-fcm).

La implementación actual reintenta 429 y errores transitorios con 100 ms y 300 ms. La documentación de Firebase recomienda respetar `Retry-After`, backoff exponencial y, para cuotas de mensajes, un retraso inicial mínimo de un minuto cuando no existe header aplicable.

Con un presupuesto de entrega de 12 segundos no siempre es posible esperar un minuto dentro de la request. La decisión debe ser diferir el intento a una cola durable, marcarlo como no entregado dentro del presupuesto sin reintentar antes del plazo del proveedor; 100/300 ms no cumplen esa política de FCM.

La documentación cloud promete que todos los intentos de un dispositivo comparten una única reserva de quota por evento. [`cloud-backend.md:83`](cloud-backend.md:83) y [`quota.rs:7`](../cloud/src/quota.rs:7) deben mantenerse alineados: si un proceso cae después de reservar y antes de persistir el resultado, el reclaim stale puede volver a reservar y violar la idempotencia documentada. La regresión debe simular ese crash, reclamar después de 30 segundos y comprobar que el contador de quota no aumenta por segunda vez.

El transfer marker `transferred_at` se escribe al transferir el runtime en [`runtimes.rs:101`](../cloud/src/runtimes.rs:101) y la ruta de upsert del target en [`transactions.rs:451`](../cloud/src/auth/transactions.rs:451) actualiza nombre y `last_seen_at` sin limpiarlo. Discovery y grant exigen el marker nulo. Puede ser una cuarentena intencional contra reactivación, pero debe quedar documentada o limpiarse mediante una operación explícita de reautorización.

Los contratos cloud y las pruebas de ownership existentes no constituyen prueba de un envío real a FCM ni de los límites externos del proveedor.

## Runtime y transporte compartido

La revisión estática encuentra una carrera concreta entre generaciones de connect/disconnect de HostLink: si `disconnect` ocurre mientras `connect` sigue pendiente, no invalida ese intento; un connect tardío puede guardar el link y publicar `Attached` después de la desconexión. La fuente es [`host_link_registry.rs:97`](../rust/alera-cli/src/terminal_host/host_link_registry.rs:97) y [`host_link_registry.rs:131`](../rust/alera-cli/src/terminal_host/host_link_registry.rs:131). La regresión debe bloquear el handshake, desconectar, liberar el handshake y comprobar que no se guarda ni se publica un link adjunto tardío.

El gateway WebSocket tiene caminos de handshake y colas cuya capacidad y ownership no quedan completamente contabilizados en el segundo review. Se requiere una prueba de conexión lenta, cliente que abandona durante handshake y productor que supera la capacidad, con cancelación verificable de la tarea spawned.

En `command_control_bytes`, las variantes `VoiceRealtime`, `VoiceTurnFinished` y `VoiceSynthesizeFinished` caen en `_ => 1` junto con otras variantes no enumeradas. La fuente es [`server_command_inbox.rs:303`](../rust/alera-cli/src/terminal_host/server/server_command_inbox.rs:303) y [`server_command.rs:387`](../rust/alera-cli/src/terminal_host/server/server_command.rs:387). Esto no es una aproximación de chunks UTF-8: excluye cargas de audio/TTS distintas y puede subestimar la admisión. La regresión debe enviar las variantes grandes y verificar que su presupuesto represente la carga o que tengan una clase explícita.

Estos puntos son hallazgos secundarios de revisión estática. No se elevan a P1 sin una reproducción dinámica que demuestre pérdida, deadlock, crecimiento sostenido o violación de un contrato observable.

## Fuentes revisadas

| Dominio | Fuentes principales |
| --- | --- |
| Hook y lifecycle | [`agent_hook_receiver.dart:116`](../lib/src/features/agent_status/infra/agent_hook_receiver.dart:116) y [`agent_hooks.rs`](../rust/src/api/agent_hooks.rs) |
| Inbox y completions | [`server_command_inbox.rs:117`](../rust/alera-cli/src/terminal_host/server/server_command_inbox.rs:117), [`server_command.rs:387`](../rust/alera-cli/src/terminal_host/server/server_command.rs:387), [`managed_workspace_requests.rs:48`](../rust/alera-cli/src/terminal_host/server/managed_workspace_requests.rs:48) |
| PTY y ACK | [`pty_events.rs`](../rust/alera-cli/src/terminal_host/server/pty_events.rs), [`session.rs`](../rust/alera-cli/src/terminal_host/session.rs) |
| AI y procesos | [`ai_assist_agent_runner.dart`](../lib/src/features/ai_assist/application/ai_assist_agent_runner.dart), [`process_output.dart`](../lib/src/shared/infra/process/process_output.dart) |
| Explorer | [`workspace_explorer.dart`](../lib/src/features/workbench/presentation/workspace_explorer.dart), [`workspace_explorer_refresh.dart`](../lib/src/features/workbench/presentation/workspace_explorer_refresh.dart) |
| Updater | [`desktop_updater_backend.dart`](../lib/src/features/updater/infra/desktop_updater_backend.dart), [`bounded_update_transport.dart`](../lib/src/features/updater/infra/bounded_update_transport.dart) |
| Edge limiter | [`index.ts:62`](../edge/src/index.ts:62) |
| FCM y transfer | [`fcm.rs`](../cloud/src/fcm.rs), [`push.rs`](../cloud/src/push.rs), [`quota.rs`](../cloud/src/quota.rs), [`runtimes.rs`](../cloud/src/runtimes.rs), [`cloud-backend.md:83`](cloud-backend.md:83) |

Las rutas anteriores documentan dónde confirmar cada hipótesis antes de diseñar un fix. La presencia de un patrón estático no implica por sí sola una regresión de usuario.

Los probes de esta revisión usaron fixtures desechables y no validaron GUI nativa de Windows o macOS, tráfico real de FCM, Cloudflare Durable Objects en producción ni navegación Back real del navegador.

## Matriz de evidencia

| Evidencia | Tipo | Resultado |
| --- | --- | --- |
| Hook nativo | Probe local con fake/runtime aislado | Cancelación depende del stop nativo; P1. |
| PTY | Probe local con productor de 20 ms | Llegadas 40, 141, 242, 260 y 337 ms; pacing aproximado de 100 ms. |
| AI process lifecycle | Fake público y proceso controlado | EOF omitido; UTF-8 inválido sin kill después de 6,001 ms. |
| Native output and voice | Probes locales | 2 MiB retenidos cuando el consumidor se conecta tarde. |
| Explorer | Dos widget probes aislados | Cambio de modo no refleja el archivo creado; proyección repetida. |
| Updater | Probe local de `file:` y permisos | Copia no se detiene tras cancelación; 512 directory mode calls sin yield. |
| Diagnostics | Dart AOT standalone | Delta RSS de 167,415,808 bytes con fixture de 50 MiB. |
| BFCache | Simulación de lifecycle | Cleanup pass; no es browser Back real. |
| Mobile RPC | 3 pruebas aisladas | Timeout y compatibilidad pass; envelopes sin respuesta esperan timeout. |
| Edge limiter | Origin fake local | Authorization rotatorio evita el 429 observado con una IP fija. |
| FCM payload | Aritmética de source y fixture | 21,863 bytes, 25 campos, reserved key sin guardia; 0 llamadas de red. |

## Estado y acciones requeridas

Los cinco P1 deben resolverse y probarse con regresiones específicas antes de declarar estable el alcance ampliado.

Las pruebas siguientes deben cubrir stop nativo concurrente, completions de inbox bajo overflow, ACK de PTY con productor continuo, UTF-8 inválido con árbol de procesos real y rate limiting de autorización ausente o inválida.

El contrato cloud debe decidir tamaño serializado y nombres reservados de FCM, retry-after y backoff, contabilidad de quota por evento o intento y ciclo de vida de `transferred_at`.

El updater debe cubrir cancelación `file:` y yields de directory mode sin degradar cleanup ni seguridad de stages.

La validación de browser, mobile y FCM debe mantenerse en sus límites probados: probes aislados, tres pruebas RPC y aritmética local no sustituyen una ejecución de producción.

No se hizo ninguna implementación derivada de este segundo review. La activación, publicación y despliegue siguen fuera de alcance por instrucción del usuario.
