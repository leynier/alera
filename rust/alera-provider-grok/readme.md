# grok provider

This crate adapts the external `grok agent stdio` process to the shared Rust provider contract through `alera-provider-acp`.

Launch and permission behavior follows the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `packages/provider-grok/src/server/acpSupport.ts` and `adapter.ts`: `XAI_API_KEY` selects the API-key auth method, cached credentials use `cached_token`, and `GROK_OAUTH2_REFERRER` defaults to the host application name while preserving explicit values.

The crate does not bundle or copy Grok source or a runtime binary. The executable is configurable and process I/O is owned by the shared bounded JSON-lines transport and ACP client.
