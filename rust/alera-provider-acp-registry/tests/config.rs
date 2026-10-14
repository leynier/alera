use alera_provider_acp_registry::{
    AcpRegistryAgentFlavor, AcpRegistryProviderConfig, AcpRegistryRecipe, AcpRegistrySource,
};
use std::ffi::OsString;
use std::path::PathBuf;

#[test]
fn registry_and_local_sources_require_their_native_identity() {
    let mut registry = AcpRegistryProviderConfig::default();
    assert!(registry.validate().is_err());
    registry.agent_id = "devin".to_owned();
    assert!(registry.validate().is_ok());

    let mut local = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "local-agent".to_owned(),
        ..Default::default()
    };
    assert!(local.validate().is_err());
    local.executable = Some(PathBuf::from("copilot"));
    assert!(local.validate().is_ok());
}

#[test]
fn known_registry_agent_flavors_are_explicit() {
    let devin = AcpRegistryProviderConfig {
        agent_id: "devin".into(),
        ..Default::default()
    };
    assert_eq!(devin.agent_flavor(), AcpRegistryAgentFlavor::Devin);

    let copilot = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "local-agent".into(),
        executable: Some("copilot.cmd".into()),
        ..Default::default()
    };
    assert_eq!(copilot.agent_flavor(), AcpRegistryAgentFlavor::Copilot);

    let mistral = AcpRegistryProviderConfig {
        agent_id: "mistral-vibe".into(),
        ..Default::default()
    };
    assert_eq!(mistral.agent_flavor(), AcpRegistryAgentFlavor::MistralVibe);
}

#[test]
fn explicit_recipe_preserves_args_env_and_auth_method() {
    let recipe = AcpRegistryRecipe {
        agent_id: "github-copilot-cli".to_owned(),
        executable: PathBuf::from("copilot"),
        args: vec![OsString::from("--acp")],
        cwd: Some(PathBuf::from("/workspace")),
        env: [(OsString::from("TOKEN"), OsString::from("redacted"))]
            .into_iter()
            .collect(),
        auth_method_id: Some("github".to_owned()),
    };
    assert!(recipe.validate().is_ok());
    assert_eq!(recipe.args, [OsString::from("--acp")]);
    assert_eq!(recipe.auth_method_id.as_deref(), Some("github"));
    let resolved = AcpRegistryProviderConfig::from_recipe(recipe).expect("resolved recipe");
    assert_eq!(resolved.agent_id, "github-copilot-cli");
    assert_eq!(resolved.executable, Some(PathBuf::from("copilot")));
}
