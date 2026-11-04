# Provider Protocol

This crate defines a UI-independent provider lifecycle and normalized runtime events. The development contract reference is [reference_projects/t3code](../../reference_projects/t3code), particularly `packages/contracts/src/providerRuntime.ts`, `providerPolicy.ts`, and `packages/provider-core/src/server/ProviderAdapter.ts`. Reference files are not runtime dependencies.

The standalone boundary keeps caller-owned thread identities separate from native provider references. An application integration must allocate and map application-owned turn, item and request identities before persisting events in an orchestration store. Unknown provider kinds, event names and raw messages remain available for forward compatibility.

The required upstream MIT copyright notice is preserved in `LICENSE`.

## Native Extensions

`Provider::steer_turn(TurnInput, expected_turn_id)` requires a provider-observed active turn precondition. `fork_session(NativeForkInput)` starts a target session on a fresh connection; its optional result native id stays absent until the provider reports it. Typed fork boundaries distinguish an inclusive native turn from an inclusive native transcript message UUID. `rollback_session(NativeRollbackInput)` changes native conversation history. `rewind_files(NativeRewindFilesInput)` restores provider-checkpointed files and is a separate operation. Every extension defaults to `ProviderError::Unsupported`; portable transcript operations are host responsibilities and do not imply these native capabilities.

`SessionStartInput.options["reasoningEffort"]` and `TurnInput.options["reasoningEffort"]` are canonical adapter inputs. `reasoning_effort_capabilities()` reports session/turn wire support separately from model-specific advertised values. Unsupported adapters or effort values fail explicitly. `native_history_capabilities()` reports supported boundary forms and filesystem rewind separately from conversation rollback.

`ProviderEvent::native_task()` decodes typed `payload.nativeTask` lineage, retaining native task, tool-call, parent-thread, and child-thread references without allocating application identities. Missing native identities are never filled with invented provider ids. Raw native frames remain authoritative for unnormalized extensions.

`Provider::upload_feedback(FeedbackUploadInput)` sends the native thread and the agent's logs to its vendor as a bug report and returns the vendor's `feedbackId`, as T3 Code's `uploadFeedback` does. It is outward-facing, so only an explicit request from the person may call it; adapters without it answer `Unsupported`.

`NativeHistoryCapabilities.fileCheckpointing` distinguishes the ability to enable checkpoints from an already-enabled session's `rewindFiles`. `NativeRewindFilesResult` retains optional provider-reported outcome/statistic fields; missing `canRewind` means unknown. Internal raw response preservation does not authorize projecting it into public recovery views.

## Shared Payloads

`Attachment::File` carries an optional `name`, the person's file name, because an uploaded file's saved path does not keep it; payloads without it still decode. `text_with_attachment_paths(text, attachments)` appends one `[Attached image|file "<name>" is saved at: <path>]` line per local attachment after the text, each after a blank line, and no length budget removes a line, as T3 Code's `providerMessageTextWithAttachmentPaths` does. `Attachment::display_name()` falls back to the saved file name, and a remote image gets no line.

`USER_INPUT_OPTION_PREVIEWS` (`optionPreviews`) is the `RuntimeRequest.payload` key for option previews: `{questionId: [preview | null, ...]}`, aligned with that question's options. It is a side channel because a typed `UserInputOption` field would break every adapter that builds options literally.

`thread.token-usage.updated` payloads and turn `tokenUsage` may carry `contextTokens` (what the provider holds now), `contextWindow` (the model's limit) and `autoCompactTokens` (where the provider compacts on its own). Each is optional and must be a nonnegative integer when present.

`CanonicalItemType::ImageGeneration` (`image_generation`) is an image the agent generated and saved on the host. `WorkflowAgent.completed_at` (`completedAt`, epoch milliseconds) is a settled member's wall-clock end; a frame that omits it keeps the earlier value within an attempt, and a restarted attempt clears it.
