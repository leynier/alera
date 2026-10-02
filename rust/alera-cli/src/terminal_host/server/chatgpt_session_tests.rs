use super::super::chatgpt_credentials::Tokens;
use super::*;

fn session_for_test(directory: &std::path::Path) -> Arc<ChatGptSession> {
    let mut session = ChatGptSession::new(directory.to_path_buf());
    session.store = CredentialStore::for_test(directory.to_path_buf());
    Arc::new(session)
}

fn account(id: &str, subject: &str) -> Account {
    Account {
        client_id: id.into(),
        subject: subject.into(),
        email: "same@example.test".into(),
        tokens: Some(Tokens {
            access_token: format!("secret-access-{id}"),
            refresh_token: None,
            id_token: format!("secret-id-{id}"),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: chrono::Utc::now().timestamp() + 3600,
        }),
    }
}

async fn install(session: &ChatGptSession, account: Account) -> HostResult<()> {
    let mut state = session.state.lock().await;
    session.load(&mut state).await?;
    session.install(&mut state, account).await
}

#[tokio::test]
async fn registrations_keep_same_email_accounts_separate_and_hide_credentials() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    install(&session, account("a", "subject-a")).await.unwrap();
    install(&session, account("b", "subject-b")).await.unwrap();
    let status = session.status().await.unwrap();
    assert_eq!(status["accounts"].as_array().unwrap().len(), 2);
    assert_eq!(status["activeClientId"], "b");
    assert_ne!(
        status["accounts"][0]["label"],
        status["accounts"][1]["label"]
    );
    assert!(!status.to_string().contains("secret-"));
    session.select("a").await.unwrap();
    assert_eq!(session.access().await.unwrap().0, "secret-access-a");
    let restarted = session_for_test(dir.path());
    assert_eq!(restarted.access().await.unwrap().0, "secret-access-a");
    assert_eq!(
        session.store.load().await.unwrap().host_id,
        restarted.store.load().await.unwrap().host_id
    );
}

#[tokio::test]
async fn incomplete_registration_can_reauthorize_without_becoming_active() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    let mut data = session.store.load().await.unwrap();
    data.accounts.push(Account {
        client_id: "issued-client".into(),
        subject: String::new(),
        email: String::new(),
        tokens: None,
    });
    session.store.save(&data).await.unwrap();
    assert!(session.select("issued-client").await.is_err());
    assert!(session.access().await.is_err());
    let response = session.start(Some("issued-client")).await.unwrap();
    let url = url::Url::parse(response["authorizationUrl"].as_str().unwrap()).unwrap();
    assert!(url
        .query_pairs()
        .any(|(key, value)| key == "client_id" && value == "issued-client"));
    assert!(!url.query_pairs().any(|(key, _)| key == "agent_name_hint"));
    session.cancel().await.unwrap();
    install(&session, account("issued-client", "verified-subject"))
        .await
        .unwrap();
    assert_eq!(
        session.status().await.unwrap()["activeClientId"],
        "issued-client"
    );
    assert_eq!(session.store.load().await.unwrap().accounts.len(), 1);
}

#[tokio::test]
async fn identity_mismatch_cannot_overwrite_an_account() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    install(&session, account("a", "subject-a")).await.unwrap();
    assert!(install(&session, account("a", "attacker")).await.is_err());
    assert_eq!(session.access().await.unwrap().0, "secret-access-a");
    assert_eq!(
        session.store.load().await.unwrap().accounts[0].subject,
        "subject-a"
    );
}

#[tokio::test]
async fn switching_and_signing_out_cancel_old_requests_and_retain_registration() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    install(&session, account("a", "subject-a")).await.unwrap();
    let (_, mut changed) = session.access().await.unwrap();
    install(&session, account("b", "subject-b")).await.unwrap();
    assert!(changed.has_changed().unwrap());
    changed.borrow_and_update();
    session.sign_out("b").await.unwrap();
    assert!(changed.has_changed().unwrap());
    assert!(session.access().await.is_err());
    let saved = session.store.load().await.unwrap();
    assert_eq!(saved.accounts.len(), 2);
    assert!(saved.accounts[1].tokens.is_none());
    assert!(saved.accounts[0].tokens.is_some());
    assert!(session.select("b").await.is_err());
    session.select("a").await.unwrap();
    assert_eq!(session.access().await.unwrap().0, "secret-access-a");
}

#[tokio::test]
async fn sign_in_cancel_keeps_the_existing_account_and_closes_listener() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    install(&session, account("a", "subject-a")).await.unwrap();
    let response = session.start(None).await.unwrap();
    assert_eq!(session.status().await.unwrap()["pending"], true);
    assert_eq!(session.access().await.unwrap().0, "secret-access-a");
    let url = url::Url::parse(response["authorizationUrl"].as_str().unwrap()).unwrap();
    let redirect = url
        .query_pairs()
        .find(|(k, _)| k == "redirect_uri")
        .unwrap()
        .1
        .into_owned();
    let port = url::Url::parse(&redirect).unwrap().port().unwrap();
    session.cancel().await.unwrap();
    tokio::task::yield_now().await;
    assert!(
        tokio::net::TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, port))
            .await
            .is_err()
    );
    assert_eq!(session.status().await.unwrap()["pending"], false);
    assert_eq!(session.access().await.unwrap().0, "secret-access-a");
}

#[tokio::test]
async fn inference_requires_granted_scope_and_welcome_is_persisted_once() {
    let dir = tempfile::tempdir().unwrap();
    let session = session_for_test(dir.path());
    let mut denied = account("a", "subject-a");
    denied.tokens.as_mut().unwrap().scopes.clear();
    install(&session, denied).await.unwrap();
    assert!(session.access().await.is_err());
    assert_eq!(session.status().await.unwrap()["showPlanNotice"], false);
    install(&session, account("a", "subject-a")).await.unwrap();
    assert_eq!(session.status().await.unwrap()["showPlanNotice"], true);
    session.acknowledge_plan().await.unwrap();
    let restarted = session_for_test(dir.path());
    assert_eq!(restarted.status().await.unwrap()["showPlanNotice"], false);
}
