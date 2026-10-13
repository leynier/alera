use std::fs::File;

use alera_core::runtime::{WorkflowLaunchInputs, WorkflowLaunchRecord};

use super::{ValidatedWorkflowLaunch, WorkflowLaunchReply};
use crate::terminal_host::host_error::HostResult;

#[allow(dead_code)]
impl ValidatedWorkflowLaunch {
    #[allow(dead_code)]
    pub(crate) fn from_test(
        reply: WorkflowLaunchReply,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
        frozen: WorkflowLaunchInputs,
        result: HostResult<()>,
    ) -> Self {
        Self {
            reply,
            record,
            token,
            locks,
            frozen,
            result,
        }
    }

    pub(crate) fn into_test_parts(
        self,
    ) -> (
        WorkflowLaunchReply,
        WorkflowLaunchRecord,
        String,
        [File; 2],
        WorkflowLaunchInputs,
        HostResult<()>,
    ) {
        (
            self.reply,
            self.record,
            self.token,
            self.locks,
            self.frozen,
            self.result,
        )
    }
}
