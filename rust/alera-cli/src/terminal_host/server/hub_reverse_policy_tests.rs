use super::*;

const ALLOWED: &[&str] = &[
    "project.list",
    "project.upsert",
    "project.rename",
    "project.hosts.list",
    "project.hosts.add",
    "project.hosts.remove",
    "project.registerRemote",
    "project.checkout.register",
    "project.removalDependencies",
    "workspace.list",
    "workspace.find",
    "workspace.createShared",
    "workspace.createManaged",
    "workspace.removeShared",
    "workspace.removeManaged",
    "workspace.remove",
    "workspace.rename",
    "workspace.setPinned",
    "workspace.unarchive",
    "workspace.handOff",
    "workspace.bufferGuard.acquire",
    "workspace.removalDependencies",
    "workspaceTag.upsert",
    "workspaceTag.assign",
    "workspaceSection.create",
    "workspaceSection.setForWorkspace",
    "workspaceRelation.link",
    "workspaceCascade.preview",
    "workspaceActivity.list",
    "projectConfig.upsert",
    "agentProfile.list",
    "agentProfile.upsert",
    "agentProfile.launch",
    "orchestration.taskCreate",
    "orchestration.dispatch",
    "orchestration.taskWait",
    "issue.fetch",
    "linkedIssue.link",
    "linkedReview.upsert",
    "pullRequestWatch.start",
    "pullRequestWatch.stop",
    "agentPresence.list",
];

const DENIED: &[&str] = &[
    "hello",
    "configure",
    "createOrAttach",
    "write",
    "terminate",
    "resize",
    "detach",
    "restored",
    "status.get",
    "terminal.create",
    "terminal.read",
    "terminal.ownerLifecycle",
    "host.process.run",
    "host.shutdown",
    "hostLink.status",
    "hostLink.request",
    "hub.forward",
    "hub.link.register",
    "hub.mirror.workspace",
    "sshTarget.list",
    "sshTarget.upsert",
    "account.status",
    "runtimeSettings.update",
    "runtimeMetadata.set",
    "mobile.hello",
    "mobile.git.status",
    "aiDictation.transcribe",
    "aiText.commitMessage.generate",
    "automation.pause",
    "automation.ownerPrecheck.start",
    "shellEnvironment.reload",
    "hostDirectory.list",
    "configuration.apply",
    "project.register",
    "project.clone.start",
    "workspace.files.write",
    "workspace.runSetup",
    "workspace.prepareRelocationSetup",
    "workspace.recoverRelocationSetup",
    "workspace.cancelRelocationSetup",
    "workspace.retirementReceipt",
    "workspace.sshRelocationRecovery",
    "git.status",
    "resources.snapshot",
    "tab.upsert",
    "agentQuota.snapshot",
    "somethingNew.unknown",
];

#[test]
fn the_table_admits_hub_owned_records_and_refuses_the_desktop_itself() {
    assert!(ALLOWED.len() >= 12 && DENIED.len() >= 12);
    for verb in ALLOWED {
        assert!(hub_answers(verb), "{verb} should be answered by the hub");
        assert!(
            refusal(verb).wire_message().contains(verb),
            "refusals name the verb"
        );
    }
    for verb in DENIED {
        assert!(!hub_answers(verb), "{verb} must stay off the hub");
    }
}

#[test]
fn forwarding_needs_a_satellite_a_local_stranger_and_an_admitted_verb() {
    let forwarding = ForwardingContext {
        satellite: true,
        authenticated: true,
        local_client: true,
        hub_link: false,
    };
    assert!(forwards_to_hub(forwarding, "workspace.createShared"));
    assert!(forwards_to_hub(forwarding, "project.hosts.add"));
    assert!(
        !forwards_to_hub(forwarding, "sshTarget.list"),
        "denied verbs stay local"
    );
    assert!(
        !forwards_to_hub(forwarding, "workspace.files.list"),
        "host-scoped verbs are the satellite's own work"
    );
    assert!(
        !forwards_to_hub(
            ForwardingContext {
                satellite: false,
                ..forwarding
            },
            "workspace.createShared"
        ),
        "an ordinary runtime answers from its own store"
    );
    assert!(
        !forwards_to_hub(
            ForwardingContext {
                hub_link: true,
                ..forwarding
            },
            "workspace.createShared"
        ),
        "the hub's own requests are handled where they land"
    );
    assert!(
        !forwards_to_hub(
            ForwardingContext {
                local_client: false,
                ..forwarding
            },
            "workspace.createShared"
        ),
        "a phone never reaches the reverse channel"
    );
    assert!(!forwards_to_hub(
        ForwardingContext {
            authenticated: false,
            ..forwarding
        },
        "workspace.createShared"
    ));
}

#[test]
fn the_origin_becomes_the_default_host_for_checkout_placing_verbs_only() {
    let created = apply_origin(
        "workspace.createShared",
        json!({"projectId": "p1", "hostId": null}),
        "lab",
    );
    assert_eq!(created["hostId"], "lab");
    assert_eq!(created["originHostId"], "lab");
    assert_eq!(created["projectId"], "p1");

    let blank = apply_origin("project.hosts.add", json!({"hostId": "  "}), "lab");
    assert_eq!(blank["hostId"], "lab", "a blank host id counts as absent");

    let explicit = apply_origin("workspace.createManaged", json!({"hostId": "other"}), "lab");
    assert_eq!(explicit["hostId"], "other", "an explicit host wins");

    let listing = apply_origin("workspace.list", json!({"hostId": "origin"}), "lab");
    assert_eq!(listing["hostId"], "lab", "`origin` resolves on every verb");

    let untouched = apply_origin("workspace.find", json!({"id": "w1"}), "lab");
    assert_eq!(untouched["originHostId"], "lab");
    assert!(
        untouched.get("hostId").is_none(),
        "a lookup does not grow a host"
    );

    let not_an_object = apply_origin("project.list", Value::Null, "lab");
    assert_eq!(not_an_object, json!({"originHostId": "lab"}));
}

#[test]
fn reply_deadlines_follow_the_verb_and_the_payloads_own_wait() {
    let minutes = |count: u64| Duration::from_secs(count * 60);
    for verb in [
        "workspace.createShared",
        "workspace.createManaged",
        "project.hosts.add",
        "project.registerRemote",
    ] {
        assert_eq!(reply_deadline(verb, &json!({})), minutes(30), "{verb}");
    }
    for verb in [
        "workspace.removeShared",
        "workspace.removeManaged",
        "workspace.remove",
        "workspace.removeForProject",
    ] {
        assert_eq!(reply_deadline(verb, &json!({})), minutes(5), "{verb}");
    }
    assert_eq!(reply_deadline("workspace.list", &json!({})), minutes(1));
    assert_eq!(reply_deadline("project.hosts.list", &json!({})), minutes(1));
    assert_eq!(
        reply_deadline("orchestration.taskWait", &json!({"timeoutMs": 120_000})),
        Duration::from_secs(150),
        "a long poll gets its wait plus a grace period"
    );
    assert_eq!(
        reply_deadline("orchestration.taskWait", &json!({"timeoutMs": 1_000})),
        minutes(1),
        "a short wait never goes below the default"
    );
    assert_eq!(
        reply_deadline("orchestration.taskWait", &json!({"timeoutMs": u64::MAX})),
        minutes(30),
        "and never above the longest provisioning deadline"
    );
}

#[test]
fn cli_listings_keep_their_shape_and_filter_by_the_resolved_host() {
    assert_eq!(
        listing_request(
            "workspace.list",
            &json!({"projectId": null, "hostId": "lab"})
        ),
        ("workspace.listAll".to_string(), json!({}))
    );
    assert_eq!(
        listing_request("workspace.list", &json!({"projectId": "p1"})),
        ("workspace.list".to_string(), json!({"projectId": "p1"}))
    );
    assert_eq!(
        listing_request("workspace.find", &json!({"id": "w1"})),
        ("workspace.find".to_string(), json!({"id": "w1"}))
    );

    let workspaces = json!([
        {"id": "a", "hostId": "lab"},
        {"id": "b", "hostId": "local"},
    ]);
    let here = listing_answer(
        "workspace.list",
        &json!({"hostId": "lab"}),
        "lab",
        workspaces.clone(),
    );
    assert_eq!(here["items"].as_array().unwrap().len(), 1);
    assert_eq!(here["items"][0]["id"], "a");
    assert_eq!(here["originHostId"], "lab");
    let all = listing_answer("workspace.list", &json!({}), "lab", workspaces.clone());
    assert_eq!(all["items"].as_array().unwrap().len(), 2);
    let projects = listing_answer("project.list", &json!({}), "lab", json!([{"id": "p1"}]));
    assert_eq!(projects["items"][0]["id"], "p1");
    assert_eq!(projects["originHostId"], "lab");
    assert_eq!(
        listing_answer("workspace.find", &json!({}), "lab", json!({"id": "w"})),
        json!({"id": "w"}),
        "other answers pass through unchanged"
    );
}

#[test]
fn the_owners_retirement_of_a_mirrored_copy_stays_on_the_satellite() {
    let retirement =
        json!({"id": "task", "expectedInstanceId": "task-instance", "closeSessions": true});
    for verb in [
        "workspace.bufferGuard.acquire",
        "workspace.removeShared",
        "workspace.removeManaged",
    ] {
        assert!(stays_with_owner(verb, &retirement, false), "{verb}");
        assert!(
            !stays_with_owner(
                verb,
                &json!({"id": "task", "expectedInstanceId": null}),
                false
            ),
            "{verb}: the CLI passes no instance and its removal travels to the hub"
        );
    }
    for verb in [
        "workspace.bufferGuard.status",
        "workspace.bufferGuard.release",
        "workspace.bufferGuard.ack",
    ] {
        assert!(
            stays_with_owner(verb, &json!({"guardId": "g1"}), true),
            "{verb}"
        );
        assert!(
            !stays_with_owner(verb, &json!({"guardId": "g1"}), false),
            "{verb}: a guard acquired on the hub is unknown here"
        );
    }
    assert!(!stays_with_owner("workspace.find", &retirement, true));
}
