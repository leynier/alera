use super::client_delivery::LocalClientRole;
use super::{ClientKind, ServerActor};
use alera_core::runtime::{AutomationActor, AutomationActorKind};

pub(super) fn actor_for_client(
    mobile: bool,
    local_role: LocalClientRole,
    id: Option<String>,
) -> AutomationActor {
    let kind = if mobile {
        AutomationActorKind::AuthenticatedMobile
    } else if local_role == LocalClientRole::App {
        AutomationActorKind::HumanDesktop
    } else {
        AutomationActorKind::LocalCli
    };
    AutomationActor {
        kind,
        id,
        label: None,
    }
}

impl ServerActor {
    pub(super) fn automation_actor(
        &self,
        client_id: u64,
        _payload: &serde_json::Value,
    ) -> AutomationActor {
        let mobile_device_id = self
            .clients
            .get(&client_id)
            .and_then(|client| client.mobile_device_id.clone());
        let actor_id = mobile_device_id.or_else(|| Some(client_id.to_string()));
        actor_for_client(
            self.clients
                .get(&client_id)
                .is_some_and(|client| client.kind == ClientKind::Mobile),
            self.clients
                .get(&client_id)
                .map(|client| client.local_role)
                .unwrap_or(LocalClientRole::Cli),
            actor_id,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authenticated_client_kind_is_the_only_actor_source() {
        let mobile = actor_for_client(true, LocalClientRole::Cli, Some("device".into()));
        assert_eq!(mobile.kind, AutomationActorKind::AuthenticatedMobile);
        assert_eq!(mobile.id.as_deref(), Some("device"));

        let app = actor_for_client(false, LocalClientRole::App, Some("client-7".into()));
        assert_eq!(app.kind, AutomationActorKind::HumanDesktop);
        assert_eq!(app.id.as_deref(), Some("client-7"));

        let cli = actor_for_client(false, LocalClientRole::Cli, Some("client-8".into()));
        assert_eq!(cli.kind, AutomationActorKind::LocalCli);
        assert_eq!(cli.id.as_deref(), Some("client-8"));
    }
}
