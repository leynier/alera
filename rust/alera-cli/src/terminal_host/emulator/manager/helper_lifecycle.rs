use uuid::Uuid;

use super::{stop_helper, AttachedDevice, EmulatorManager, EmulatorResult, StreamHelper};
use crate::terminal_host::emulator::video_server::VideoSource;

impl StreamHelper {
    fn is_healthy(&mut self) -> bool {
        match self {
            Self::Android(stream) => stream.is_healthy(),
            Self::Ios(helper) => helper.is_healthy(),
        }
    }
}

impl EmulatorManager {
    pub(super) async fn ensure_helper(&mut self, tab_id: &str) -> EmulatorResult<bool> {
        let helper_state = match self.session_mut(tab_id)?.helper.as_mut() {
            Some(helper) => {
                if helper.is_healthy() {
                    return Ok(false);
                }
                HelperState::Failed
            }
            None => HelperState::Missing,
        };
        if helper_state == HelperState::Failed {
            let helper = self.session_mut(tab_id)?.helper.take();
            self.session_mut(tab_id)?.stream_url = None;
            self.video.remove(tab_id).await;
            stop_helper(&self.android, self.session(tab_id)?, helper).await;
        }

        let token = Uuid::new_v4().simple().to_string();
        let (helper, source) = match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                let stream = self.android.start_stream(&attached.serial).await?;
                let source = VideoSource::Android(stream.source.clone());
                (StreamHelper::Android(stream), source)
            }
            AttachedDevice::Ios(attached) => {
                let helper = self.ios.start_helper(&attached.udid).await?;
                let source = VideoSource::Proxy {
                    url: helper.stream_url.clone(),
                    healthy: helper.stream_health(),
                };
                (StreamHelper::Ios(helper), source)
            }
        };
        let url = self.video.register(tab_id, token, source).await;
        let session = self.session_mut(tab_id)?;
        session.helper = Some(helper);
        session.stream_url = Some(url);
        Ok(helper_state == HelperState::Failed)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum HelperState {
    Missing,
    Failed,
}
