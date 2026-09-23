use super::*;

pub(super) async fn run_mobile_command(command: MobileCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        MobileAction::Status => {
            let runtime_host_active =
                match RuntimeHostRpcClient::connect_mobile(&runtime_dir(&runtime)).await {
                    Ok(client) => client.is_some(),
                    Err(_) => false,
                };
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            match mobile_status(&store, Some(runtime_host_active)).await {
                Ok(status) => print_value(&status, json_output, "mobile status ready"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Enable(args) => {
            let request = MobileSettingsUpdateRequest {
                enabled: Some(true),
                remote_access_enabled: None,
                bind_host: args.bind_host,
                port: args.port,
                endpoint_mode: if args.netbird {
                    Some(MobileEndpointMode::Netbird)
                } else {
                    args.tailscale.then_some(MobileEndpointMode::Tailscale)
                },
                netbird_endpoint: args.netbird.then_some(args.netbird_endpoint.into()),
            };
            match mobile_runtime_host_request::<MobileAccessSettings, _>(
                &runtime,
                "mobile.settings.update",
                &request,
            )
            .await
            {
                Ok(settings) => print_value(&settings, json_output, "mobile access enabled"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Disable => {
            let request = MobileSettingsUpdateRequest {
                enabled: Some(false),
                remote_access_enabled: None,
                bind_host: None,
                port: None,
                endpoint_mode: None,
                netbird_endpoint: None,
            };
            let fallback_request = request.clone();
            match mobile_runtime_host_or_store(
                &runtime,
                "mobile.settings.update",
                &request,
                |store| async move { update_mobile_settings(&store, fallback_request).await },
            )
            .await
            {
                Ok(settings) => print_value(&settings, json_output, "mobile access disabled"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Pairing(command) => match command.action {
            MobilePairingAction::Create(args) => {
                let request = MobilePairingCreateRequest {
                    endpoint: args.endpoint,
                    device_name: args.device_name,
                    expires_minutes: args.expires_minutes,
                };
                match mobile_runtime_host_request::<MobilePairingOfferPayload, _>(
                    &runtime,
                    "mobile.pairing.create",
                    &request,
                )
                .await
                {
                    Ok(offer) => print_value(&offer, json_output, "mobile pairing offer created"),
                    Err(error) => return print_error(error),
                }
            }
            MobilePairingAction::Claim(args) => {
                let request = MobileDevicePairRequest {
                    pairing_id: args.pairing_id,
                    pairing_secret: args.pairing_secret,
                    device_name: args.device_name,
                    public_key_b64: args.public_key_b64,
                };
                let fallback_request = request.clone();
                match mobile_runtime_host_or_store(
                    &runtime,
                    "mobile.device.pair",
                    &request,
                    |store| async move { pair_mobile_device(&store, fallback_request).await },
                )
                .await
                {
                    Ok(device) => print_value(&device, json_output, "mobile device paired"),
                    Err(error) => return print_error(error),
                }
            }
            MobilePairingAction::Cancel(IdArgs { id }) => {
                let payload = json!({ "id": id });
                let cancelled_id = id.clone();
                match mobile_runtime_host_or_store_unit(
                    &runtime,
                    "mobile.pairing.cancel",
                    &payload,
                    |store| async move { cancel_mobile_pairing_offer(&store, &id).await },
                )
                .await
                {
                    Ok(()) => print_value(
                        &json!({ "id": cancelled_id }),
                        json_output,
                        "mobile pairing offer cancelled",
                    ),
                    Err(error) => return print_error(error),
                }
            }
        },
        MobileAction::Devices(command) => {
            match command.action {
                MobileDevicesAction::List(args) => {
                    let payload = json!({ "includeRevoked": args.include_revoked });
                    match mobile_runtime_host_or_store(
                    &runtime,
                    "mobile.device.list",
                    &payload,
                    |store| async move { list_mobile_devices(&store, args.include_revoked).await },
                )
                .await
                {
                    Ok(devices) => print_value(&json!({ "kind": "mobileDevices", "items": devices, "filters": { "includeRevoked": args.include_revoked } }), json_output, "mobile devices listed"),
                    Err(error) => return print_error(error),
                }
                }
                MobileDevicesAction::Rename(args) => {
                    let payload = json!({ "id": args.id, "displayName": args.name });
                    match mobile_runtime_host_or_store::<MobileDeviceSummary, _, _>(
                        &runtime,
                        "mobile.device.rename",
                        &payload,
                        |store| async move {
                            rename_mobile_device(&store, &args.id, &args.name).await
                        },
                    )
                    .await
                    {
                        Ok(device) => print_value(&device, json_output, "mobile device renamed"),
                        Err(error) => return print_error(error),
                    }
                }
                MobileDevicesAction::Revoke(IdArgs { id }) => {
                    let payload = json!({ "id": id });
                    let revoked_id = id.clone();
                    match mobile_runtime_host_or_store_unit(
                        &runtime,
                        "mobile.device.revoke",
                        &payload,
                        |store| async move { revoke_mobile_device(&store, &id).await },
                    )
                    .await
                    {
                        Ok(()) => print_value(
                            &json!({ "id": revoked_id }),
                            json_output,
                            "mobile device revoked",
                        ),
                        Err(error) => return print_error(error),
                    }
                }
                MobileDevicesAction::Delete(IdArgs { id }) => {
                    let payload = json!({ "id": id });
                    let deleted_id = id.clone();
                    match mobile_runtime_host_or_store_unit(
                        &runtime,
                        "mobile.device.delete",
                        &payload,
                        |store| async move { delete_mobile_device(&store, &id).await },
                    )
                    .await
                    {
                        Ok(()) => print_value(
                            &json!({ "id": deleted_id }),
                            json_output,
                            "mobile device deleted",
                        ),
                        Err(error) => return print_error(error),
                    }
                }
            }
        }
    }
    0
}
