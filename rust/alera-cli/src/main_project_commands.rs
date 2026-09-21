use super::*;

pub(super) async fn run_project_command(command: ProjectCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        ProjectAction::List => match open_store(&runtime).await {
            Ok(store) => match store.list_projects().await {
                Ok(projects) => {
                    let mut items = json!(projects);
                    crate::project_hosts::decorate_projects(&store, &mut items).await;
                    print_value(
                        &json!({ "kind": "projects", "items": items, "filters": {} }),
                        json_output,
                        "projects listed",
                    )
                }
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        ProjectAction::Hosts(command) => {
            use crate::cli::ProjectHostsAction;
            let (request_type, payload, message, deadline_ms) = match command.action {
                ProjectHostsAction::List(args) => (
                    "project.hosts.list",
                    json!({ "projectId": args.project_id }),
                    "project hosts listed",
                    30_000,
                ),
                // A clone can take as long as the repository is large.
                ProjectHostsAction::Add(args) => (
                    "project.hosts.add",
                    json!({
                        "projectId": args.project_id, "hostId": args.host_id,
                        "path": args.path, "cloneUrl": args.clone_url,
                    }),
                    "project added to host",
                    1_800_000,
                ),
                ProjectHostsAction::Remove(args) => (
                    "project.hosts.remove",
                    json!({ "projectId": args.project_id, "hostId": args.host_id }),
                    "project removed from host",
                    30_000,
                ),
            };
            let mut client = match runtime_host_required(&runtime).await {
                Ok(client) => client,
                Err(error) => return print_error(error),
            };
            match client
                .request_value_with_deadline(request_type, &payload, deadline_ms)
                .await
            {
                Ok(value) => print_value(&value, json_output, message),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::OwnerTerminal(args) => {
            return match remote_owner_terminal::run(args).await {
                Ok(code) => code,
                Err(error) => print_error(error),
            };
        }
        ProjectAction::ControlOwnerTerminal(args) => {
            match remote_owner_terminal_lifecycle::run(args).await {
                Ok(value) => print_value(&value, true, "owner terminal closure verified"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::RelocateOwnerWorkspace(args) => {
            match remote_owner_relocation::run(args).await {
                Ok(value) => print_value(&value, true, "owner workspace relocated"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::ControlOwnerSetup(args) => match remote_owner_setup::run(args).await {
            Ok(value) => print_value(&value, true, "owner setup updated"),
            Err(error) => return print_error(error),
        },
        ProjectAction::ControlOwnerPrecheck(args) => match remote_owner_precheck::run(args).await {
            Ok(value) => print_value(&value, true, "owner precheck state inspected"),
            Err(error) => return print_error(error),
        },
        ProjectAction::InspectOwnerRecovery(args) => match remote_owner_recovery::run(args).await {
            Ok(value) => print_value(&value, true, "owner recovery inspected"),
            Err(error) => return print_error(error),
        },
        ProjectAction::RetireOwnerWorkspace(args) => {
            match remote_owner_retirement::run(args).await {
                Ok(receipt) => print_value(&receipt, true, "remote task retired"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::RegisterOwnerWorkspace(args) => {
            match remote_workspace_owner::run(args).await {
                Ok(workspace) => print_value(&workspace, true, "remote owner registered"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::CloneCheckoutFolder(args) => {
            match project_checkout_clone::clone_checkout(args).await {
                Ok(checkout) => print_value(&checkout, true, "checkout cloned"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::CreateCheckoutWorktree(args) => {
            match project_checkout_worktree::create(args).await {
                Ok(checkout) => print_value(&checkout, true, "worktree created"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::RegisterCheckout(args) => {
            let mut client = match runtime_host_required(&runtime).await {
                Ok(client) => client,
                Err(error) => return print_error(error),
            };
            match client
                .request_value_with_deadline(
                    "project.checkout.register",
                    &json!({
                        "projectId": args.project_id, "hostId": args.host_id, "path": args.path, "cloneUrl": args.clone_url,
                    }),
                    1_800_000,
                )
                .await
            {
                Ok(checkout) => print_value(&checkout, json_output, "checkout registered"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::InspectCheckoutFiles(args) => {
            match project_file_catalog::inspect(args.path).await {
                Ok(value) => print_value(&value, true, "checkout files inspected"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::InspectCheckoutBranches(args) => {
            match project_branch_catalog::inspect(args.path).await {
                Ok(value) => print_value(&value, true, "checkout branches inspected"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::InspectLinkedCheckout(args) => {
            match project_checkout_inspection::inspect_linked(args.path).await {
                Ok(checkout) => print_value(&checkout, true, "linked checkout inspected"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::InspectCheckout(args) => {
            match project_checkout_inspection::inspect(
                args.path,
                match args.kind {
                    ProjectKindArg::GitRepository => {
                        alera_core::runtime::ProjectKind::GitRepository
                    }
                    ProjectKindArg::Folder => alera_core::runtime::ProjectKind::Folder,
                },
            )
            .await
            {
                Ok(checkout) => print_value(&checkout, true, "checkout inspected"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::Add(args) => {
            let kind = match args.kind {
                ProjectKindArg::GitRepository => ProjectKind::GitRepository,
                ProjectKindArg::Folder => ProjectKind::Folder,
            };
            let payload = json!({"path":args.repo_path,"name":args.name,"id":args.id,"kind":kind});
            match runtime_host_or_store(
                &runtime,
                "project.register",
                &payload,
                |store| async move {
                    project_management::register_project_with_identity(
                        &store,
                        &args.repo_path,
                        Some(&args.name),
                        args.id.as_deref(),
                        Some(kind),
                    )
                    .await
                },
            )
            .await
            {
                Ok(registration) => print_value(&registration, json_output, "project registered"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::Remove(args) => {
            let id = args.id;
            if args.pause_automations_and_cancel_runs {
                let mut client = match runtime_host_required(&runtime).await {
                    Ok(client) => client,
                    Err(error) => return print_error(error),
                };
                if let Err(error) =
                    workspace_removal_dependencies::prepare_cli_project_removal_dependencies(
                        &mut client,
                        &id,
                        true,
                    )
                    .await
                {
                    return print_error(error);
                }
                return match client
                    .request_value("project.remove", &json!({"id": id}))
                    .await
                {
                    Ok(_) => {
                        print_value(&json!({"id":id}), json_output, "project removed");
                        0
                    }
                    Err(error) => print_error(error),
                };
            }
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(
                &runtime,
                "project.remove",
                &payload,
                |store| async move { hosted_review_retention::remove_project(store, &id).await },
            )
            .await
            {
                Ok(()) => print_value(&json!({ "id": removed_id }), json_output, "project removed"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}
