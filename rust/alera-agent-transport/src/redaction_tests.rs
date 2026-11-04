use super::{redact_secrets, REDACTED};

#[test]
fn masks_compound_credential_key_names() {
    let redacted = redact_secrets(
        "OPENAI_API_KEY=key-one MY_SECRET=secret-two GITHUB_TOKEN=token-three \
         x_api_key: key-four AWS_SECRET_ACCESS_KEY=key-five deviceToken=token-six",
    );

    assert_eq!(
        redacted,
        "OPENAI_API_KEY=[redacted] MY_SECRET=[redacted] GITHUB_TOKEN=[redacted] \
         x_api_key: [redacted] AWS_SECRET_ACCESS_KEY=[redacted] deviceToken=[redacted]"
    );
}

#[test]
fn masks_keys_that_end_in_a_credential_word() {
    let code = redact_secrets(r#"{"refresh_token":"code value"}"#);
    let message = redact_secrets(
        r#"oauth refresh failed: client_secret=client-value refresh_token=refresh-value {"client_secret":"json-value"} clientSecret: camel-value X-Auth-Token: header-value max_tokens=4096"#,
    );

    assert_eq!(code, r#"{"refresh_token":"[redacted]"}"#);
    assert_eq!(
        message,
        r#"oauth refresh failed: client_secret=[redacted] refresh_token=[redacted] {"client_secret":"[redacted]"} clientSecret: [redacted] X-Auth-Token: [redacted] max_tokens=4096"#
    );
}

#[test]
fn masks_credentials_and_url_secrets_in_provider_failures() {
    let redacted = redact_secrets(
        r#"request failed: Authorization: Bearer bearer-secret https://user:pass@example.test/path?access_token=url-secret#fragment {"token":"json-secret"} api_key=key-secret sk-abcdefghijklmnop"#,
    );

    assert!(redacted.contains("https://[redacted]@example.test/path"));
    assert!(redacted.contains("Authorization: Bearer [redacted]"));
    for (index, secret) in [
        "bearer-secret",
        "user:pass",
        "url-secret",
        "json-secret",
        "key-secret",
        "sk-abcdefghijklmnop",
    ]
    .into_iter()
    .enumerate()
    {
        assert!(
            !redacted.contains(secret),
            "fixture secret #{index} was not redacted"
        );
    }
}

#[test]
fn masks_provider_keys_whose_body_contains_underscores() {
    let redacted = redact_secrets(
        "anthropic=sk-ant-api03-AbCdEf_GhIjKlMnOpQr-StUvWx_yz0123456789-AA\n\
         openai=sk-proj-AbCdEfGhIj_KlMnOpQrStUv-WxYz_0123456789",
    );

    assert_eq!(redacted, "anthropic=[redacted]\nopenai=[redacted]");
}

#[test]
fn masks_prefixed_tokens_and_header_credentials() {
    let redacted = redact_secrets(
        "openai=sk-proj-abcdefghijklmnopqrstuvwxyz012345\n\
         svc=sk-svcacct-abcdefghijklmnopqrstuvwxyz012345\n\
         github=ghp_abcdefghijklmnopqrstuvwxyz0123456789 pat=github_pat_11ABCDEFG0123456789_abcdef\n\
         slack=xoxb-123456789012-abcdefghijkl\n\
         Authorization: Basic dXNlcjpwYXNz\n\
         x-api-key: ant-api-key-value",
    );

    assert!(redacted.contains("Authorization: Basic [redacted]"));
    assert!(redacted.contains("x-api-key: [redacted]"));
    for (index, secret) in [
        "sk-proj-",
        "sk-svcacct-",
        "abcdefghijklmnopqrstuvwxyz012345",
        "ghp_",
        "github_pat_",
        "xoxb-",
        "dXNlcjpwYXNz",
        "ant-api-key-value",
    ]
    .into_iter()
    .enumerate()
    {
        assert!(
            !redacted.contains(secret),
            "fixture secret #{index} was not redacted"
        );
    }
}

#[test]
fn masks_bearer_tokens_without_a_key() {
    let redacted = redact_secrets("retrying with bearer eyJhbGciOiJIUzI1NiJ9.payload~sig");

    assert_eq!(redacted, "retrying with bearer [redacted]");
}

#[test]
fn keeps_the_shape_of_quoted_values() {
    let redacted = redact_secrets(
        r#"{'password': 'hunter2 hunter2', "apiKey": "a\"b", "token": "", "secret": "cut"#,
    );

    assert_eq!(
        redacted,
        r#"{'password': '[redacted]', "apiKey": "[redacted]", "token": "", "secret": "[redacted]"#
    );
}

#[test]
fn masks_url_passwords_but_keeps_plain_account_names() {
    let redacted = redact_secrets(
        "proxy https://token-only@proxy.test and postgres://app:pw@db.test/app \
         and ssh://git@github.com/org/repo.git",
    );

    assert_eq!(
        redacted,
        "proxy https://[redacted]@proxy.test and postgres://[redacted]@db.test/app \
         and ssh://git@github.com/org/repo.git"
    );
}

#[test]
fn leaves_ordinary_words_untouched() {
    for message in [
        "failed to record activity for workspace ws-17: database is locked",
        "usage: max_tokens=4096 input_tokens: 12 tokenizer=cl100k token_count=3",
        "secretary: Ada passwordless=true keyboard=us monkey=banana",
        "Token refresh failed: invalid_grant; Authorization failed with 401",
        "task-abcdefghijklmnop finished, ask-questions-later",
        "señal añadida: ñandú",
    ] {
        assert_eq!(redact_secrets(message), message);
    }
}

#[test]
fn does_not_reach_across_lines_for_a_value() {
    let redacted = redact_secrets("missing token:\nplease sign in again");

    assert_eq!(redacted, "missing token:\nplease sign in again");
}

#[test]
fn redacting_twice_is_stable() {
    let once = redact_secrets("GITHUB_TOKEN=abc Authorization: Bearer xyz sk-abcdefghijklmnop");

    assert!(once.contains(REDACTED));
    assert_eq!(redact_secrets(&once), once);
}
