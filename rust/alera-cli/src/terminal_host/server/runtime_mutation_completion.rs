use super::runtime_mutations::RuntimeMutationCompletion;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn apply_runtime_mutation_completion(
        &mut self,
        completion: RuntimeMutationCompletion,
    ) -> serde_json::Value {
        let RuntimeMutationCompletion {
            response,
            effect,
            hand_on_relocate,
            ..
        } = completion;
        if let Some(relocate) = hand_on_relocate {
            self.relocate_sessions_after_hand_on(
                &relocate.source_workspace_id,
                &relocate.destination_workspace_id,
                &relocate.source_path,
                &relocate.dest_path,
            );
            self.checkpoint_transferred_workspace(&relocate.destination_workspace_id)
                .await;
            self.broadcast_workspace_tabs_changed(Some(&relocate.destination_workspace_id));
        }
        self.apply_runtime_mutation_effect(effect).await;
        response
    }
}
