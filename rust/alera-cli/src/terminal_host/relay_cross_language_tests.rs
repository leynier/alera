use super::*;
use serde_json::json;

struct FixtureAccount {
    origin: String,
    http: reqwest::Client,
}
impl RelayAccount for FixtureAccount {
    fn relay_identity(
        &self,
    ) -> futures_util::future::BoxFuture<'_, anyhow::Result<IdentityKeyPair>> {
        Box::pin(async { Ok(IdentityKeyPair::from_private([2; 32])) })
    }
    fn relay_grant(&self) -> futures_util::future::BoxFuture<'_, anyhow::Result<RelayGrant>> {
        Box::pin(async {
            Ok(self
                .http
                .get(format!(
                    "{}/fixture/grant?role=runtime&client=fixture-runtime",
                    self.origin
                ))
                .send()
                .await?
                .error_for_status()?
                .json()
                .await?)
        })
    }
}

#[tokio::test]
#[ignore = "run edge/tool/relay_integration.mjs with Flutter and workerd"]
async fn relay_cross_language_fixture() {
    let origin = std::env::var("ALERA_RELAY_TEST_ORIGIN").expect("local fixture origin");
    assert!(origin.starts_with("http://127.0.0.1:"));
    let account = FixtureAccount {
        origin: origin.clone(),
        http: reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .unwrap(),
    };
    let verifier = GrantVerifier::with_url(
        "https://relay-fixture.test".into(),
        format!("{origin}/.well-known/jwks.json"),
    )
    .unwrap();
    let (inbox, mut commands) = mpsc::unbounded_channel();
    let ids = Arc::new(AtomicU64::new(1));
    let mut backoff = RelayRetryBackoff::default();
    let transport = connect_and_serve(
        &account,
        "fixture-runtime",
        &inbox,
        &ids,
        &verifier,
        &mut backoff,
        1,
    );
    tokio::pin!(transport);
    let mut handles = HashMap::<u64, ClientHandle>::new();
    let mut connected = 0;
    let mut memory = sysinfo::System::new();
    let pid = sysinfo::get_current_pid().unwrap();
    let mut peak_memory = 0;
    let mut poll = tokio::time::interval(Duration::from_secs(1));
    let deadline = tokio::time::sleep(Duration::from_secs(
        std::env::var("ALERA_RELAY_TEST_SECONDS")
            .unwrap()
            .parse::<u64>()
            .unwrap()
            + 90,
    ));
    tokio::pin!(deadline);
    loop {
        tokio::select! {
            result = &mut transport => panic!("relay transport ended unexpectedly: {result:?}"),
            _ = &mut deadline => panic!("relay fixture exceeded its deadline"),
            _ = poll.tick() => {
                memory.refresh_processes_specifics(sysinfo::ProcessesToUpdate::Some(&[pid]), true, sysinfo::ProcessRefreshKind::nothing().without_tasks().with_memory());
                peak_memory = peak_memory.max(memory.process(pid).map_or(0, sysinfo::Process::memory));
                let value: serde_json::Value = account.http.get(format!("{origin}/fixture/done")).send().await.unwrap().json().await.unwrap();
                if value["done"] == true { assert!(connected >= 1); println!("RELAY_RUNTIME_METRICS {}", json!({"connections":connected,"peakSampledRssBytes":peak_memory})); break; }
            }
            command = commands.recv() => match command.unwrap() {
                ServerCommand::RelayStatus { payload, .. } if payload["state"] == "connected" => println!("RELAY_FIXTURE_READY"),
                ServerCommand::RelayClientConnected { id, handle, .. } => { connected += 1; handles.insert(id, handle); }
                ServerCommand::RelayClientLine { id, line, accepted, expires_at } => {
                    assert!(expires_at > chrono::Utc::now().timestamp());
                    let request: serde_json::Value = serde_json::from_str(&line).unwrap();
                    let payload = if request["type"] == "mobile.hello" {
                        json!({ "binaryFrames": true, "runtimeCapabilities": ["relayAuthorizationRenewalV1"] })
                    } else { request["payload"].clone() };
                    if let Some(handle) = handles.get(&id) {
                        let _ = handle.send_control(ClientFrame::Json(json!({ "id": request["id"], "ok": true, "payload": payload })));
                    }
                    if request["type"] == "mobile.hello" { handles[&id].send_control(ClientFrame::UpgradeToBinary).unwrap(); }
                    let _ = accepted.send(());
                }
                ServerCommand::ClientDisconnected { id } => { handles.remove(&id); }
                _ => {}
            }
        }
    }
}
