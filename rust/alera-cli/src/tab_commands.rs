//! `alera tab`: list, create, remove, rename, and link workspace tabs.

use serde_json::json;

use crate::cli::{TabAction, TabCommand, TabRemoveArgs};
use crate::tab_record_factory::tab_from_args;
use crate::{
    open_store, print_error, print_value, runtime_host_or_store, runtime_host_or_store_unit,
    USAGE_EXIT_CODE,
};

pub(crate) async fn run(command: TabCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        action @ (TabAction::Rename(_) | TabAction::GenerateTitle(_)) => {
            return crate::terminal_lifecycle_commands::run_tab(&runtime, action, json_output)
                .await;
        }
        TabAction::Remove(args) if args.terminate => {
            return crate::terminal_lifecycle_commands::run_tab(
                &runtime,
                TabAction::Remove(args),
                json_output,
            )
            .await;
        }
        TabAction::LinkAgent(args) => {
            return crate::tab_agent_link_command::run(&runtime, args, json_output).await;
        }
        TabAction::List(args) => match open_store(&runtime).await {
            Ok(store) => match store.list_workspace_tabs(&args.workspace_id).await {
                Ok(tabs) => print_value(
                    &json!({ "kind": "tabs", "items": tabs, "filters": { "workspaceId": args.workspace_id } }),
                    json_output,
                    "tabs listed",
                ),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        TabAction::Create(args) => {
            let tab = match tab_from_args(args) {
                Ok(tab) => tab,
                Err(error) => {
                    eprintln!("{error}");
                    return USAGE_EXIT_CODE;
                }
            };
            let fallback_tab = tab.clone();
            match runtime_host_or_store(&runtime, "tab.upsert", &tab, |store| async move {
                store.upsert_workspace_tab(fallback_tab).await
            })
            .await
            {
                Ok(tab) => print_value(&tab, json_output, "tab saved"),
                Err(error) => return print_error(error),
            }
        }
        TabAction::Remove(TabRemoveArgs { id, .. }) => {
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(&runtime, "tab.remove", &payload, |store| async move {
                if let Some(tab) = store.find_workspace_tab(&id).await? {
                    if tab.kind == "terminal" {
                        if let Some(workspace) = store.find_workspace(&tab.workspace_id).await? {
                            if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                                anyhow::bail!("The Home runtime must be available to verify SSH terminal closure before removing this tab");
                            }
                        }
                    }
                }
                let retentions = crate::hosted_review_retention::for_tab(&store, &id).await;
                store.remove_workspace_tab(&id).await?;
                crate::hosted_review_retention::release(retentions);
                Ok(())
            })
            .await
            {
                Ok(()) => print_value(&json!({ "id": removed_id }), json_output, "tab removed"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}
