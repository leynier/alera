use super::*;
use gpui::AppContext as _;
use super::super::editor_requests::{EditorKey, EditorRequests};

fn document(content: &str, token: &str) -> EditorDocument {
    EditorDocument { relative_path: "same.txt".into(), raw_content: content.into(), display_content: content.into(), content_token: token.into() }
}

fn key(owner: &str) -> EditorKey { EditorKey { workspace: owner.into(), path: "same.txt".into() } }

#[gpui::test]
fn editor_save_all_collects_live_dirty_targets_across_workspace_banks(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let a = cx.new(|cx| EditorState::new(window, cx));
        let b = cx.new(|cx| EditorState::new(window, cx));
        let clean = cx.new(|cx| EditorState::new(window, cx));
        a.update(cx, |input, cx| input.set_value("a dirty", window, cx));
        b.update(cx, |input, cx| input.set_value("b dirty", window, cx));
        clean.update(cx, |input, cx| input.set_value("baseline", window, cx));
        let mut bank = EditorWorkspaces::default();
        let mut active = bank.switch(Some("a".into()), WorkspaceEditors::default());
        active.inputs.insert("same.txt".into(), a.clone());
        active.documents.insert("same.txt".into(), document("a baseline", "a0"));
        let mut active = bank.switch(Some("b".into()), active);
        active.inputs.insert("same.txt".into(), b.clone());
        active.documents.insert("same.txt".into(), document("b baseline", "b0"));
        active.inputs.insert("clean.txt".into(), clean);
        active.documents.insert("clean.txt".into(), document("baseline", "c0"));
        let targets = bank.save_targets(&active, cx).into_iter().map(|target| (target.key, target.editor)).collect::<BTreeMap<_, _>>();
        assert_eq!(targets.len(), 2);
        assert_eq!(targets[&key("a")], a.entity_id());
        assert_eq!(targets[&key("b")], b.entity_id());
        active.load_errors.insert("same.txt".into());
        assert_eq!(bank.save_targets(&active, cx).len(), 1, "a failed read is not eligible for Save All");
        active.load_errors.clear();
        bank.retain_live_tabs(&[]);
        assert_eq!(bank.save_targets(&active, cx).len(), 1, "retired parked tabs must not be saved");
    });
}

#[gpui::test]
fn editor_replace_invalidates_clean_parked_documents_without_losing_new_edits(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let clean = cx.new(|cx| EditorState::new(window, cx));
        clean.update(cx, |input, cx| input.set_value("baseline", window, cx));
        let dirty = cx.new(|cx| EditorState::new(window, cx));
        dirty.update(cx, |input, cx| input.set_value("new edit before event", window, cx));
        let mut state = WorkspaceEditors::default();
        state.inputs.insert("clean.txt".into(), clean.clone());
        state.inputs.insert("dirty.txt".into(), dirty.clone());
        state.documents.insert("clean.txt".into(), document("baseline", "c0"));
        state.documents.insert("dirty.txt".into(), document("baseline", "d0"));
        state.buffers.insert("clean.txt".into(), "baseline".into());
        let mut bank = EditorWorkspaces::default();
        let empty = bank.switch(Some("a".into()), WorkspaceEditors::default());
        assert!(empty.inputs.is_empty());
        bank.switch(Some("b".into()), state);
        let affected = BTreeSet::from(["clean.txt".into(), "dirty.txt".into()]);
        let invalidated = bank.parked.get_mut("a").unwrap().invalidate_clean_paths(&affected, cx);
        assert_eq!(invalidated, BTreeSet::from(["clean.txt".into()]));
        assert!(!bank.parked["a"].documents.contains_key("clean.txt"));
        assert!(!bank.parked["a"].buffers.contains_key("clean.txt"));
        assert!(bank.parked["a"].documents.contains_key("dirty.txt"));
        assert_eq!(dirty.read(cx).value().as_str(), "new edit before event");
        assert_eq!(bank.owner.as_deref(), Some("b"));
    });
}

#[gpui::test]
async fn editor_writes_accept_reversed_responses_in_their_own_workspaces(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    let (mut bank, mut active, mut requests, first, second) = cx.update(|window, cx| {
        let a = cx.new(|cx| EditorState::new(window, cx));
        a.update(cx, |input, cx| input.set_value("a saved", window, cx));
        let b = cx.new(|cx| EditorState::new(window, cx));
        b.update(cx, |input, cx| input.set_value("b newer edit", window, cx));
        let mut bank = EditorWorkspaces::default();
        let mut active = bank.switch(Some("a".into()), WorkspaceEditors::default());
        active.inputs.insert("same.txt".into(), a.clone());
        active.documents.insert("same.txt".into(), document("a original", "a0"));
        active.dirty.insert("same.txt".into());
        let mut requests = EditorRequests::default();
        let first = requests.begin_write(key("a"), a.entity_id(), "/a".into(), "a saved".into(), false).unwrap();
        let mut active = bank.switch(Some("b".into()), active);
        active.inputs.insert("same.txt".into(), b.clone());
        active.documents.insert("same.txt".into(), document("b original", "b0"));
        active.dirty.insert("same.txt".into());
        let second = requests.begin_write(key("b"), b.entity_id(), "/b".into(), "b saved".into(), false).unwrap();
        (bank, active, requests, first, second)
    });
    let (send_a, receive_a) = futures::channel::oneshot::channel();
    let (send_b, receive_b) = futures::channel::oneshot::channel();
    send_b.send(document("b saved", "b1")).unwrap();
    let result_b = receive_b.await.unwrap();
    cx.update(|_, cx| {
        assert!(requests.finish_write(&second));
        assert!(bank.accept_saved(&mut active, &second, result_b, cx));
        assert_eq!(active.documents["same.txt"].content_token, "b1");
        assert_eq!(active.buffers["same.txt"], "b newer edit");
        assert!(active.dirty.contains("same.txt"));
        assert!(requests.is_writing(&key("a")));
    });
    send_a.send(document("a saved", "a1")).unwrap();
    let result_a = receive_a.await.unwrap();
    cx.update(|_, cx| {
        assert!(requests.finish_write(&first));
        assert!(bank.accept_saved(&mut active, &first, result_a, cx));
        assert_eq!(bank.owner.as_deref(), Some("b"));
        assert_eq!(bank.parked["a"].documents["same.txt"].content_token, "a1");
        assert!(!bank.parked["a"].dirty.contains("same.txt"));
        assert_eq!(active.inputs["same.txt"].read(cx).value().as_str(), "b newer edit");
        assert!(!requests.finish_write(&first));
    });
}

#[gpui::test]
fn editor_writes_do_not_resurrect_closed_or_reopened_entities(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let old = cx.new(|cx| EditorState::new(window, cx));
        let new = cx.new(|cx| EditorState::new(window, cx));
        new.update(cx, |input, cx| input.set_value("reopened edit", window, cx));
        let mut requests = EditorRequests::default();
        let request = requests.begin_write(key("a"), old.entity_id(), "/a".into(), "old save".into(), false).unwrap();
        requests.retain_live_tabs(&[]);
        assert!(requests.is_writing(&key("a")), "disk write remains serialized after tab closure");
        assert!(requests.begin_write(key("a"), new.entity_id(), "/a".into(), "new save".into(), false).is_none());
        let mut state = WorkspaceEditors::default();
        state.inputs.insert("same.txt".into(), new.clone());
        state.documents.insert("same.txt".into(), document("reopened baseline", "new0"));
        assert!(requests.finish_write(&request));
        assert!(!state.accept_saved(&request, document("old save", "old1"), cx));
        assert_eq!(state.documents["same.txt"].content_token, "new0");
        assert_eq!(new.read(cx).value().as_str(), "reopened edit");
        let fresh = requests.begin_write(key("a"), new.entity_id(), "/a".into(), "new save".into(), false).unwrap();
        assert!(!requests.finish_write(&request));
        assert!(requests.is_writing(&key("a")));
        assert!(requests.finish_write(&fresh));
    });
}

#[gpui::test]
fn editor_autosave_and_conflict_tokens_are_document_scoped(cx: &mut gpui::TestAppContext) {
    let entity = cx.new(|_| gpui::Empty);
    let mut requests = EditorRequests::default();
    let a = requests.schedule_auto(key("a"), entity.entity_id());
    let b = requests.schedule_auto(key("b"), entity.entity_id());
    let newer_a = requests.schedule_auto(key("a"), entity.entity_id());
    assert!(!requests.take_auto(&a));
    assert!(requests.take_auto(&b));
    assert!(requests.take_auto(&newer_a));
    let write = requests.begin_write(key("a"), entity.entity_id(), "/a".into(), "value".into(), false).unwrap();
    assert!(requests.finish_write(&write));
    requests.fail(&write, "file changed on disk".into());
    let confirmation = requests.confirmation(&key("a")).unwrap();
    assert!(requests.confirmation(&key("b")).is_none());
    let retry = requests.begin_write(key("a"), entity.entity_id(), "/a".into(), "value".into(), false).unwrap();
    assert!(requests.confirmation(&key("a")).is_none());
    requests.finish_write(&retry);
    requests.fail(&retry, "file changed on disk".into());
    assert_ne!(requests.confirmation(&key("a")).unwrap(), confirmation);
}

#[gpui::test]
fn editor_workspace_switch_keeps_entities_and_same_path_drafts_separate(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let a = cx.new(|cx| EditorState::new(window, cx));
        a.update(cx, |input, cx| input.set_value("alpha draft", window, cx));
        let b = cx.new(|cx| EditorState::new(window, cx));
        b.update(cx, |input, cx| input.set_value("beta draft", window, cx));
        let mut bank = EditorWorkspaces::default();
        let mut active = bank.switch(Some("a".into()), WorkspaceEditors::default());
        active.inputs.insert("same.txt".into(), a.clone());
        active.buffers.insert("same.txt".into(), "alpha draft".into());
        active.dirty.insert("same.txt".into());
        let mut active = bank.switch(Some("b".into()), active);
        assert!(active.inputs.is_empty());
        active.inputs.insert("same.txt".into(), b.clone());
        active.buffers.insert("same.txt".into(), "beta draft".into());
        let active = bank.switch(Some("a".into()), active);
        assert_eq!(active.inputs["same.txt"], a);
        assert_eq!(active.inputs["same.txt"].read(cx).value().as_str(), "alpha draft");
        assert!(active.dirty.contains("same.txt"));
        assert_eq!(bank.parked["b"].inputs["same.txt"], b);
        bank.retain_live_tabs(&[]);
        assert!(bank.parked.is_empty());
    });
}
