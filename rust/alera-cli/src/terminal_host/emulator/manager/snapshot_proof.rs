use std::io::Cursor;
use std::path::PathBuf;
use std::time::Instant;

use png::{BitDepth, ColorType, Transformations};
use serde_json::{json, Value};
use sha2::{Digest as _, Sha256};
use uuid::Uuid;

use super::{
    AttachedDevice, EmulatorFailure, EmulatorManager, EmulatorResult, StreamHelper, SNAPSHOT_TTL,
};

pub(super) struct SnapshotProof {
    pub(super) tab_id: String,
    pub(super) generation: u64,
    pub(super) created_at: Instant,
    pub(super) tree_digest: [u8; 32],
    pub(super) frame_digest: [u8; 32],
    pub(super) screenshot_path: Option<PathBuf>,
}

struct CapturedFrame {
    digest: [u8; 32],
    screenshot_path: Option<PathBuf>,
}

impl CapturedFrame {
    fn screenshot_value(&self) -> Option<Value> {
        self.screenshot_path
            .as_ref()
            .map(|path| json!({"path": path, "expiresInSeconds": 600}))
    }

    fn commit(mut self) -> ([u8; 32], Option<PathBuf>) {
        (self.digest, self.screenshot_path.take())
    }
}

impl Drop for CapturedFrame {
    fn drop(&mut self) {
        super::remove_screenshot(self.screenshot_path.as_deref());
    }
}

struct TemporaryScreenshot(Option<PathBuf>);

impl TemporaryScreenshot {
    fn new(path: PathBuf) -> Self {
        Self(Some(path))
    }

    fn into_captured(mut self, digest: [u8; 32]) -> CapturedFrame {
        CapturedFrame {
            digest,
            screenshot_path: self.0.take(),
        }
    }
}

impl Drop for TemporaryScreenshot {
    fn drop(&mut self) {
        super::remove_screenshot(self.0.as_deref());
    }
}

impl EmulatorManager {
    pub async fn snapshot(
        &mut self,
        tab_id: &str,
        include_screenshot: bool,
    ) -> EmulatorResult<Value> {
        if matches!(self.session(tab_id)?.attached, AttachedDevice::Ios(_)) {
            self.ensure_helper(tab_id).await?;
        }
        let snapshot_id = Uuid::new_v4().to_string();
        let frame = self
            .capture_visual_frame(tab_id, &snapshot_id, include_screenshot)
            .await?;
        let screenshot = frame.screenshot_value();
        let tree = self.accessibility_tree(tab_id).await?;
        let session = self.session(tab_id)?;
        let generation = session.generation;
        let session_id = session.tab_id.clone();
        let device_id = session.device_id.clone();
        let (frame_digest, screenshot_path) = frame.commit();
        if let Some(path) = screenshot_path.clone() {
            schedule_screenshot_removal(path);
        }
        self.prune_expired_snapshots();
        self.snapshots.insert(
            snapshot_id.clone(),
            SnapshotProof {
                tab_id: tab_id.to_string(),
                generation,
                created_at: Instant::now(),
                tree_digest: Sha256::digest(tree.as_bytes()).into(),
                frame_digest,
                screenshot_path,
            },
        );
        Ok(json!({
            "ok": true,
            "snapshot": {
                "snapshotId": snapshot_id,
                "sessionId": session_id,
                "deviceId": device_id,
                "coordinateSpace": "normalized",
                "origin": "topLeft",
                "treeText": tree,
                "screenshot": screenshot,
            }
        }))
    }

    pub(super) fn validate_snapshot(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
    ) -> EmulatorResult<()> {
        let Some(snapshot_id) = snapshot_id else {
            return Err(EmulatorFailure::new(
                "snapshot_required",
                "Automation actions require a current emulator snapshot.",
                ["Capture a snapshot and retry with its snapshot id."],
            ));
        };
        self.prune_expired_snapshots();
        let session = self.session(tab_id)?;
        if self.snapshots.get(snapshot_id).is_some_and(|proof| {
            proof.tab_id == tab_id
                && proof.generation == session.generation
                && proof.created_at.elapsed() <= SNAPSHOT_TTL
        }) {
            return Ok(());
        }
        Err(stale_snapshot(
            "The emulator state changed after that snapshot.",
        ))
    }

    pub(super) async fn validate_snapshot_state(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
    ) -> EmulatorResult<()> {
        self.validate_snapshot(tab_id, snapshot_id)?;
        let expected = self
            .snapshots
            .get(snapshot_id.expect("validation requires a snapshot id"))
            .map(|proof| (proof.tree_digest, proof.frame_digest))
            .expect("validation retained the snapshot proof");
        if matches!(self.session(tab_id)?.attached, AttachedDevice::Ios(_)) {
            self.ensure_helper(tab_id).await?;
        }
        let capture_id = format!("proof-{}", Uuid::new_v4());
        let current_frame = self
            .capture_visual_frame(tab_id, &capture_id, false)
            .await?
            .digest;
        let current_tree = self.accessibility_tree(tab_id).await?;
        let current_tree_digest = <[u8; 32]>::from(Sha256::digest(current_tree.as_bytes()));
        if current_tree_digest == expected.0 && current_frame == expected.1 {
            return Ok(());
        }
        Err(stale_snapshot(
            "The emulator visual or accessibility state changed after that snapshot.",
        ))
    }

    pub(super) fn invalidate_snapshots(&mut self, tab_id: &str) -> EmulatorResult<()> {
        let generation = self.session(tab_id)?.generation.wrapping_add(1);
        self.session_mut(tab_id)?.generation = generation;
        self.remove_snapshot_proofs_for_tab(tab_id);
        Ok(())
    }

    fn prune_expired_snapshots(&mut self) {
        self.snapshots.retain(|_, proof| {
            let keep = proof.created_at.elapsed() <= SNAPSHOT_TTL;
            if !keep {
                super::remove_screenshot(proof.screenshot_path.as_deref());
            }
            keep
        });
    }

    async fn capture_visual_frame(
        &self,
        tab_id: &str,
        capture_id: &str,
        persist: bool,
    ) -> EmulatorResult<CapturedFrame> {
        let path = self.snapshot_dir.join(format!("{capture_id}.png"));
        match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                let bytes = self.android.screenshot(&attached.serial).await?;
                decode_android_frame(bytes, persist.then_some(path)).await
            }
            AttachedDevice::Ios(attached) => {
                let temporary = TemporaryScreenshot::new(path.clone());
                self.ios.screenshot(&attached.udid, &path).await?;
                let read_path = path.clone();
                let digest = tokio::task::spawn_blocking(move || {
                    let bytes = std::fs::read(read_path).map_err(screenshot_failure)?;
                    decoded_pixel_digest(&bytes).map_err(frame_decode_failure)
                })
                .await
                .map_err(|error| frame_decode_failure(error.to_string()))??;
                if persist {
                    Ok(temporary.into_captured(digest))
                } else {
                    drop(temporary);
                    Ok(CapturedFrame {
                        digest,
                        screenshot_path: None,
                    })
                }
            }
        }
    }

    async fn accessibility_tree(&self, tab_id: &str) -> EmulatorResult<String> {
        match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                self.android.accessibility_tree(&attached.serial).await
            }
            AttachedDevice::Ios(_) => match self.session(tab_id)?.helper.as_ref() {
                Some(StreamHelper::Ios(helper)) => {
                    serde_json::to_string_pretty(&self.ios.accessibility_tree(helper).await?)
                        .map_err(|error| {
                            EmulatorFailure::new(
                                "provider_incompatible",
                                format!("Could not encode the iOS accessibility tree: {error}"),
                                ["Retry the snapshot."],
                            )
                        })
                }
                _ => Err(EmulatorFailure::new(
                    "no_active_emulator",
                    "The iOS stream is not active.",
                    ["Acquire the emulator stream and retry."],
                )),
            },
        }
    }
}

async fn decode_android_frame(
    bytes: Vec<u8>,
    screenshot_path: Option<PathBuf>,
) -> EmulatorResult<CapturedFrame> {
    tokio::task::spawn_blocking(move || {
        let digest = decoded_pixel_digest(&bytes).map_err(frame_decode_failure)?;
        let Some(path) = screenshot_path else {
            return Ok(CapturedFrame {
                digest,
                screenshot_path: None,
            });
        };
        let temporary = TemporaryScreenshot::new(path);
        std::fs::write(
            temporary
                .0
                .as_deref()
                .expect("temporary screenshot owns its path"),
            bytes,
        )
        .map_err(screenshot_failure)?;
        Ok(temporary.into_captured(digest))
    })
    .await
    .map_err(|error| frame_decode_failure(error.to_string()))?
}

fn decoded_pixel_digest(bytes: &[u8]) -> Result<[u8; 32], String> {
    let mut decoder = png::Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(Transformations::EXPAND | Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|error| error.to_string())?;
    let size = reader.output_buffer_size().ok_or_else(|| {
        "Decoded screenshot dimensions exceed the host address space.".to_string()
    })?;
    let mut decoded = vec![0; size];
    let info = reader
        .next_frame(&mut decoded)
        .map_err(|error| error.to_string())?;
    if info.bit_depth != BitDepth::Eight {
        return Err("Decoded screenshot did not normalize to 8-bit color.".into());
    }
    let mut digest = Sha256::new();
    digest.update(b"alera-emulator-frame-v1");
    digest.update(info.width.to_le_bytes());
    digest.update(info.height.to_le_bytes());
    update_rgba_digest(&mut digest, info.color_type, &decoded[..info.buffer_size()])?;
    Ok(digest.finalize().into())
}

fn update_rgba_digest(
    digest: &mut Sha256,
    color_type: ColorType,
    pixels: &[u8],
) -> Result<(), String> {
    match color_type {
        ColorType::Grayscale => {
            for value in pixels {
                digest.update([*value, *value, *value, 255]);
            }
        }
        ColorType::GrayscaleAlpha => {
            for pair in pixels.as_chunks::<2>().0 {
                digest.update([pair[0], pair[0], pair[0], pair[1]]);
            }
        }
        ColorType::Rgb => {
            for rgb in pixels.as_chunks::<3>().0 {
                digest.update([rgb[0], rgb[1], rgb[2], 255]);
            }
        }
        ColorType::Rgba => digest.update(pixels),
        ColorType::Indexed => {
            return Err("Decoded screenshot retained an indexed color palette.".into());
        }
    }
    Ok(())
}

fn stale_snapshot(message: &str) -> EmulatorFailure {
    EmulatorFailure::new(
        "snapshot_stale",
        message,
        ["Capture a new snapshot and retry with its snapshot id."],
    )
}

fn screenshot_failure(error: impl ToString) -> EmulatorFailure {
    EmulatorFailure::new(
        "permission_denied",
        format!(
            "Could not save the private emulator screenshot: {}",
            error.to_string()
        ),
        ["Check permissions for the Alera runtime directory."],
    )
}

fn frame_decode_failure(error: impl ToString) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        format!(
            "Could not decode the emulator screenshot for visual verification: {}",
            error.to_string()
        ),
        ["Retry after the visible screen settles."],
    )
}

fn schedule_screenshot_removal(path: PathBuf) {
    tokio::spawn(async move {
        tokio::time::sleep(SNAPSHOT_TTL).await;
        let _ = std::fs::remove_file(path);
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode_rgba(width: u32, height: u32, pixels: &[u8], label: Option<&str>) -> Vec<u8> {
        let mut output = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut output, width, height);
            encoder.set_color(ColorType::Rgba);
            encoder.set_depth(BitDepth::Eight);
            if let Some(label) = label {
                encoder
                    .add_text_chunk("Description".into(), label.into())
                    .unwrap();
            }
            let mut writer = encoder.write_header().unwrap();
            writer.write_image_data(pixels).unwrap();
        }
        output
    }

    #[test]
    fn decoded_pixel_digest_uses_dimensions_and_pixel_colors() {
        let black = encode_rgba(1, 1, &[0, 0, 0, 255], None);
        let white = encode_rgba(1, 1, &[255, 255, 255, 255], None);
        let wide_black = encode_rgba(2, 1, &[0, 0, 0, 255, 0, 0, 0, 255], None);

        assert_ne!(
            decoded_pixel_digest(&black).unwrap(),
            decoded_pixel_digest(&white).unwrap()
        );
        assert_ne!(
            decoded_pixel_digest(&black).unwrap(),
            decoded_pixel_digest(&wide_black).unwrap()
        );
    }

    #[test]
    fn decoded_pixel_digest_ignores_png_metadata() {
        let plain = encode_rgba(1, 1, &[10, 20, 30, 255], None);
        let labeled = encode_rgba(1, 1, &[10, 20, 30, 255], Some("Different Metadata"));

        assert_ne!(plain, labeled);
        assert_eq!(
            decoded_pixel_digest(&plain).unwrap(),
            decoded_pixel_digest(&labeled).unwrap()
        );
    }
}
