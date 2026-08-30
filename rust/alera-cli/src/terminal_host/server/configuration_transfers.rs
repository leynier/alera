use anyhow::{bail, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

pub(super) const MAX_BYTES: usize = 2 * 1024 * 1024;
const CHUNK_BYTES: usize = 128 * 1024;
const MAX_TRANSFERS: usize = 8;
const TTL: Duration = Duration::from_secs(300);

struct Transfer {
    id: String,
    account: String,
    action: String,
    size: usize,
    bytes: Vec<u8>,
    expires: Instant,
}

#[derive(Default)]
pub(super) struct ConfigurationTransfers {
    clients: HashMap<u64, Transfer>,
}

impl ConfigurationTransfers {
    pub(super) fn disconnect(&mut self, client: u64) {
        self.clients.remove(&client);
    }

    pub(super) fn start(
        &mut self,
        client: u64,
        account: &str,
        action: &str,
        size: usize,
        bytes: Vec<u8>,
    ) -> Result<Value> {
        self.clients.retain(|_, t| t.expires > Instant::now());
        if size == 0 || size > MAX_BYTES || bytes.len() > size {
            bail!("Configuration transfer is outside the supported range.");
        }
        if !self.clients.contains_key(&client) && self.clients.len() >= MAX_TRANSFERS {
            bail!("Too many configuration transfers. Try again later.");
        }
        let id = uuid::Uuid::new_v4().to_string();
        self.clients.insert(
            client,
            Transfer {
                id: id.clone(),
                account: account.into(),
                action: action.into(),
                size,
                bytes,
                expires: Instant::now() + TTL,
            },
        );
        Ok(json!({"transferId": id, "size": size}))
    }

    fn get(&mut self, client: u64, account: &str, id: &str) -> Result<&mut Transfer> {
        self.clients.retain(|_, t| t.expires > Instant::now());
        let transfer = self
            .clients
            .get_mut(&client)
            .ok_or_else(|| anyhow::anyhow!("Configuration transfer expired. Review again."))?;
        if transfer.account != account || transfer.id != id {
            bail!("Configuration transfer does not belong to this client and account.");
        }
        Ok(transfer)
    }

    pub(super) fn read(
        &mut self,
        client: u64,
        account: &str,
        id: &str,
        offset: usize,
    ) -> Result<Value> {
        let t = self.get(client, account, id)?;
        if t.action != "snapshot" || offset >= t.bytes.len() {
            bail!("Invalid configuration read offset.");
        }
        let end = offset.saturating_add(CHUNK_BYTES).min(t.bytes.len());
        Ok(json!({"data": STANDARD.encode(&t.bytes[offset..end])}))
    }

    pub(super) fn chunk(
        &mut self,
        client: u64,
        account: &str,
        id: &str,
        offset: usize,
        data: &str,
    ) -> Result<Value> {
        if data.len() > CHUNK_BYTES.div_ceil(3) * 4 {
            bail!("Configuration chunk is too large.");
        }
        let bytes = STANDARD.decode(data)?;
        let t = self.get(client, account, id)?;
        if t.action == "snapshot"
            || bytes.is_empty()
            || bytes.len() > CHUNK_BYTES
            || offset != t.bytes.len()
            || offset.saturating_add(bytes.len()) > t.size
        {
            bail!("Invalid configuration chunk sequence.");
        }
        t.bytes.extend_from_slice(&bytes);
        Ok(json!({}))
    }

    pub(super) fn take(
        &mut self,
        client: u64,
        account: &str,
        id: &str,
    ) -> Result<(String, Vec<u8>)> {
        let t = self.get(client, account, id)?;
        if t.action == "snapshot" || t.bytes.len() != t.size {
            bail!("Configuration transfer is incomplete.");
        }
        let t = self.clients.remove(&client).unwrap();
        Ok((t.action, t.bytes))
    }

    pub(super) fn cancel(&mut self, client: u64, account: &str, id: &str) -> Result<Value> {
        self.get(client, account, id)?;
        self.clients.remove(&client);
        Ok(json!({}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn configuration_transfers_bound_and_isolate_chunks() {
        let mut transfers = ConfigurationTransfers::default();
        assert!(transfers
            .start(1, "a", "apply", MAX_BYTES + 1, vec![])
            .is_err());
        let meta = transfers.start(1, "a", "apply", 3, vec![]).unwrap();
        let id = meta["transferId"].as_str().unwrap();
        assert!(transfers.chunk(2, "a", id, 0, "YWJj").is_err());
        assert!(transfers.chunk(1, "b", id, 0, "YWJj").is_err());
        assert!(transfers.take(1, "a", id).is_err());
        assert!(transfers.chunk(1, "a", id, 1, "YWJj").is_err());
        transfers.chunk(1, "a", id, 0, "YWJj").unwrap();
        assert_eq!(
            transfers.take(1, "a", id).unwrap(),
            ("apply".into(), b"abc".to_vec())
        );
        assert!(transfers.take(1, "a", id).is_err());
    }
    #[test]
    fn configuration_snapshot_transfers_reassemble_large_documents() {
        let mut transfers = ConfigurationTransfers::default();
        let bytes = vec![42; 3 * 512 * 1024];
        let meta = transfers
            .start(1, "a", "snapshot", bytes.len(), bytes.clone())
            .unwrap();
        let id = meta["transferId"].as_str().unwrap();
        let mut actual = Vec::new();
        while actual.len() < bytes.len() {
            let chunk = transfers.read(1, "a", id, actual.len()).unwrap();
            actual.extend(STANDARD.decode(chunk["data"].as_str().unwrap()).unwrap());
        }
        assert_eq!(actual, bytes);
        transfers.clients.get_mut(&1).unwrap().expires = Instant::now();
        assert!(transfers.read(1, "a", id, 0).is_err());
    }
}
