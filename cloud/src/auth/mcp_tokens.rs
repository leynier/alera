use chrono::{DateTime, TimeDelta, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{api_models::ClientKind, error::ApiError};

use super::{
    tokens::{invalid_token, ACCESS_TOKEN_SECONDS},
    AccessClaims, TokenService,
};

pub const MCP_CALL_GRANT_SECONDS: i64 = 120;
pub const MCP_CALL_AUDIENCE: &str = "alera-runtime-mcp";

pub struct McpAccessInput<'a> {
    pub account_id: Uuid,
    pub family_id: Uuid,
    pub client_id: &'a str,
    pub grant_id: Uuid,
    pub scope: &'a str,
    pub authenticated_at: DateTime<Utc>,
}

pub struct McpCallGrantInput<'a> {
    pub call_id: Uuid,
    pub account_id: Uuid,
    pub runtime_id: &'a str,
    pub grant_id: Uuid,
    pub client_id: &'a str,
    pub client_name: &'a str,
    pub tool: &'a str,
    pub access: &'a str,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpCallGrantClaims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
    pub nbf: i64,
    pub jti: String,
    pub account_id: Uuid,
    pub runtime_id: String,
    pub grant_id: Uuid,
    pub client_id: String,
    pub client_name: String,
    pub tool: String,
    pub access: String,
}

impl TokenService {
    pub async fn issue_mcp(&self, input: McpAccessInput<'_>) -> Result<String, ApiError> {
        let now = Utc::now();
        let claims = AccessClaims {
            iss: self.issuer.clone(),
            sub: input.account_id.to_string(),
            aud: self.mcp_resource.clone(),
            exp: (now + TimeDelta::seconds(ACCESS_TOKEN_SECONDS)).timestamp(),
            iat: now.timestamp(),
            nbf: (now - TimeDelta::seconds(5)).timestamp(),
            jti: Uuid::now_v7().to_string(),
            sid: input.family_id.to_string(),
            client_id: input.client_id.to_owned(),
            client_kind: ClientKind::Mcp.as_str().to_owned(),
            auth_time: input.authenticated_at.timestamp(),
            scope: input.scope.to_owned(),
            gid: Some(input.grant_id.to_string()),
        };
        self.sign_jwt("at+jwt", &claims).await
    }

    /// Verifies an access token issued for the MCP resource.
    pub fn verify_mcp(&self, token: &str) -> Result<AccessClaims, ApiError> {
        let claims: AccessClaims = self.verify_jwt(token, "at+jwt", &self.mcp_resource)?;
        if claims.client_kind != ClientKind::Mcp.as_str() || claims.gid.is_none() {
            return Err(invalid_token());
        }
        Ok(claims)
    }

    pub async fn issue_mcp_call_grant(
        &self,
        input: McpCallGrantInput<'_>,
    ) -> Result<String, ApiError> {
        let now = Utc::now();
        let claims = McpCallGrantClaims {
            iss: self.issuer.clone(),
            sub: input.account_id.to_string(),
            aud: MCP_CALL_AUDIENCE.to_owned(),
            exp: (now + TimeDelta::seconds(MCP_CALL_GRANT_SECONDS)).timestamp(),
            iat: now.timestamp(),
            nbf: (now - TimeDelta::seconds(5)).timestamp(),
            jti: input.call_id.to_string(),
            account_id: input.account_id,
            runtime_id: input.runtime_id.to_owned(),
            grant_id: input.grant_id,
            client_id: input.client_id.to_owned(),
            client_name: input.client_name.to_owned(),
            tool: input.tool.to_owned(),
            access: input.access.to_owned(),
        };
        self.sign_jwt("mcp-call+jwt", &claims).await
    }

    pub fn verify_mcp_call_grant(&self, token: &str) -> Result<McpCallGrantClaims, ApiError> {
        self.verify_jwt(token, "mcp-call+jwt", MCP_CALL_AUDIENCE)
    }
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use crate::{
        api_models::ClientKind,
        auth::tokens::tests::{decode_claims, test_service},
        mcp_models::ToolAccess,
    };

    use super::{McpAccessInput, McpCallGrantInput};

    #[tokio::test]
    async fn mcp_tokens_are_rejected_by_cloud_routes() {
        let service = test_service().with_mcp_resource("https://issuer.example/v1/mcp".to_owned());
        let grant_id = Uuid::now_v7();
        let token = service
            .issue_mcp(McpAccessInput {
                account_id: Uuid::now_v7(),
                family_id: Uuid::now_v7(),
                client_id: "mcp_client",
                grant_id,
                scope: "mcp:read",
                authenticated_at: Utc::now(),
            })
            .await
            .unwrap_or_default();
        assert!(service.verify(&token).is_err());
        let claims = match service.verify_mcp(&token) {
            Ok(value) => value,
            Err(error) => panic!("unexpected token error: {error}"),
        };
        assert_eq!(claims.gid, Some(grant_id.to_string()));
        assert_eq!(claims.aud, "https://issuer.example/v1/mcp");
        assert_eq!(claims.client_kind, "mcp");
        assert_eq!(claims.scope, "mcp:read");

        let cloud = service
            .issue(
                Uuid::now_v7(),
                Uuid::now_v7(),
                "runtime-1",
                ClientKind::Runtime,
                Utc::now(),
            )
            .await
            .unwrap_or_default();
        assert!(service.verify_mcp(&cloud).is_err());
    }

    #[tokio::test]
    async fn call_grants_carry_camel_case_claims() {
        let service = test_service();
        let call_id = Uuid::now_v7();
        let grant = service
            .issue_mcp_call_grant(McpCallGrantInput {
                call_id,
                account_id: Uuid::now_v7(),
                runtime_id: "runtime-1",
                grant_id: Uuid::now_v7(),
                client_id: "mcp_client",
                client_name: "Claude",
                tool: "update_runtime_settings",
                access: ToolAccess::Admin.as_str(),
            })
            .await
            .unwrap_or_default();
        let header = grant.split('.').next().unwrap_or_default();
        assert!(String::from_utf8(
            base64::Engine::decode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, header)
                .unwrap_or_default()
        )
        .unwrap_or_default()
        .contains("mcp-call+jwt"));
        let claims = decode_claims(&grant);
        assert_eq!(claims["aud"], "alera-runtime-mcp");
        assert_eq!(claims["jti"], call_id.to_string());
        assert_eq!(claims["clientName"], "Claude");
        assert_eq!(claims["runtimeId"], "runtime-1");
        assert_eq!(claims["access"], "admin");
        let lifetime =
            claims["exp"].as_i64().unwrap_or_default() - claims["iat"].as_i64().unwrap_or_default();
        assert_eq!(lifetime, 120);
        assert!(service.verify_mcp_call_grant(&grant).is_ok());
        assert!(service.verify(&grant).is_err());
    }
}
