use std::{
    collections::HashSet,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
};

use futures::future::BoxFuture;
use gpui::http_client::{
    self, http::HeaderValue, AsyncBody, HttpClient, Request, Response, StatusCode, Url,
};
use gpui::{ImageSource, SharedUri};
use reqwest_client::ReqwestClient;

const MAX_AUTHORIZED_LOCAL_IMAGES: usize = 4096;

static AUTHORIZED_LOCAL_IMAGES: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();

pub(crate) fn register_local_image_path(path: PathBuf) {
    if !path.is_absolute() {
        return;
    }
    let paths = AUTHORIZED_LOCAL_IMAGES.get_or_init(|| Mutex::new(HashSet::new()));
    if let Ok(mut paths) = paths.lock() {
        if paths.len() >= MAX_AUTHORIZED_LOCAL_IMAGES {
            if let Some(candidate) = paths.iter().next().cloned() {
                paths.remove(&candidate);
            }
        }
        paths.insert(path);
    }
}

pub(crate) fn image_source(uri: &SharedUri) -> ImageSource {
    let uri_string = uri.to_string();
    let Some(path) = decode_file_uri(&uri_string) else {
        return ImageSource::from(uri.clone());
    };
    let authorized = AUTHORIZED_LOCAL_IMAGES
        .get()
        .and_then(|paths| paths.lock().ok())
        .is_some_and(|paths| paths.contains(&path));
    if authorized {
        ImageSource::from(path)
    } else {
        ImageSource::from(uri.clone())
    }
}

pub(crate) struct AleraImageHttpClient {
    remote: Arc<ReqwestClient>,
}

impl AleraImageHttpClient {
    pub(crate) fn new() -> Self {
        Self {
            remote: Arc::new(ReqwestClient::new()),
        }
    }
}

impl HttpClient for AleraImageHttpClient {
    fn user_agent(&self) -> Option<&HeaderValue> {
        self.remote.user_agent()
    }

    fn proxy(&self) -> Option<&Url> {
        self.remote.proxy()
    }

    fn send(
        &self,
        request: Request<AsyncBody>,
    ) -> BoxFuture<'static, anyhow::Result<Response<AsyncBody>>> {
        let uri = request.uri().to_string();
        if !uri.starts_with("file://") {
            return self.remote.send(request);
        }

        Box::pin(async move {
            let path = decode_file_uri(&uri)
                .ok_or_else(|| http_client::anyhow!("invalid local image URI"))?;
            let authorized = AUTHORIZED_LOCAL_IMAGES
                .get()
                .and_then(|paths| paths.lock().ok())
                .is_some_and(|paths| paths.contains(&path));
            if !authorized {
                return Err(http_client::anyhow!(
                    "local image is outside the active workspace"
                ));
            }
            let bytes = std::fs::read(path)?;
            Response::builder()
                .status(StatusCode::OK)
                .body(AsyncBody::from(bytes))
                .map_err(Into::into)
        })
    }
}

fn decode_file_uri(uri: &str) -> Option<PathBuf> {
    let encoded = uri.strip_prefix("file://")?;
    let encoded = encoded.strip_prefix("localhost").unwrap_or(encoded);
    let bytes = encoded.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let high = (bytes[index + 1] as char).to_digit(16)?;
            let low = (bytes[index + 2] as char).to_digit(16)?;
            decoded.push(((high << 4) | low) as u8);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8(decoded).ok().map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::decode_file_uri;

    #[test]
    fn decodes_local_image_uris() {
        assert_eq!(
            decode_file_uri("file:///tmp/alera%20image.webp")
                .expect("the URI should decode")
                .to_string_lossy(),
            "/tmp/alera image.webp"
        );
    }
}
