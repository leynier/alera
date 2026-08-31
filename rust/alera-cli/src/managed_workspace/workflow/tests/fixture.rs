use std::path::PathBuf;

use super::*;

pub(super) struct Fixture {
    _dir: tempfile::TempDir,
    pub runtime: PathBuf,
    pub source: PathBuf,
    pub store: RuntimeStore,
    pub plan: WorkflowPlanRevision,
}

impl Fixture {
    pub async fn new(setup: &str) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let runtime = dir.path().join("runtime");
        let source = dir.path().join("source");
        let repo = git2::Repository::init(&source).unwrap();
        repo.config().unwrap().set_str("user.name", "Test").unwrap();
        repo.config()
            .unwrap()
            .set_str("user.email", "test@example.com")
            .unwrap();
        std::fs::write(source.join("shared.txt"), "initial").unwrap();
        let mut index = repo.index().unwrap();
        index.add_path(Path::new("shared.txt")).unwrap();
        let tree = index.write_tree().unwrap();
        let signature = git2::Signature::now("Test", "test@example.com").unwrap();
        let sha = repo
            .commit(
                Some("HEAD"),
                &signature,
                &signature,
                "initial",
                &repo.find_tree(tree).unwrap(),
                &[],
            )
            .unwrap();
        let store = RuntimeStore::open(&runtime).await.unwrap();
        sqlx::query("INSERT INTO projects(id,name,repoPath,createdAt,updatedAt,kind)
            VALUES('project','Project',?,'2026-08-30T00:00:00Z','2026-08-30T00:00:00Z','gitRepository')")
            .bind(source.to_str().unwrap()).execute(store.pool()).await.unwrap();
        sqlx::query("INSERT INTO workspaces(id,instanceId,hostId,projectId,name,path,createdAt,updatedAt,kind,status)
            VALUES('owner','instance','local','project','Owner',?,'2026-08-30T00:00:00Z','2026-08-30T00:00:00Z','main','active')")
            .bind(source.to_str().unwrap()).execute(store.pool()).await.unwrap();
        store
            .set_workspace_directory(Some(
                dir.path().join("workspaces").to_string_lossy().as_ref(),
            ))
            .await
            .unwrap();
        if !setup.is_empty() {
            std::fs::write(
                source.join("alera.toml"),
                format!(
                    "[worktree]\nsetup = [{}]\n",
                    serde_json::to_string(setup).unwrap()
                ),
            )
            .unwrap();
        }
        let now = Utc::now();
        store
            .upsert_agent_profile(
                AgentProfile {
                    id: "profile".into(),
                    name: "Agent".into(),
                    sort_order: 0,
                    agent_type: "codex".into(),
                    command: "codex".into(),
                    launch_mode: AgentProfileLaunchMode::Command,
                    managed_config: None,
                    custom_prompt: String::new(),
                    description: String::new(),
                    quota_group: None,
                    revision: 0,
                    created_at: now,
                    updated_at: now,
                },
                None,
            )
            .await
            .unwrap();
        let recipe = &builtin_workflow_recipes()[0];
        let mut tasks = recipe
            .stages
            .iter()
            .map(|stage| WorkflowPlanTask {
                id: stage.id.clone(),
                title: stage.name.clone(),
                spec: stage.purpose.clone(),
                stage_id: stage.id.clone(),
                role_id: stage.roles[0].clone(),
                depends_on: vec![],
                inputs: json!({"objective":"Scoped change"}),
                corrects_task_id: None,
            })
            .collect::<Vec<_>>();
        let mut second = tasks[0].clone();
        second.id = "other".into();
        tasks.insert(1, second);
        let mut spare = tasks[0].clone();
        spare.id = "spare".into();
        tasks.insert(2, spare);
        let plan = store
            .prepare_workflow_plan(
                PrepareWorkflowPlan {
                    request_id: Uuid::new_v4().to_string(),
                    workspace_id: "owner".into(),
                    run_id: None,
                    expected_revision: None,
                    proposal: WorkflowPlanProposal {
                        objective: "Scoped change".into(),
                        source_sha: sha.to_string(),
                        recipe_source: WorkflowRecipeSource::BuiltIn {
                            id: recipe.id.clone(),
                        },
                        expected_recipe_digest: recipe.content_digest().unwrap(),
                        coordinator_profile_id: "profile".into(),
                        role_profiles: recipe
                            .roles
                            .iter()
                            .map(|role| (role.id.clone(), "profile".into()))
                            .collect(),
                        max_concurrent: 2,
                        tasks,
                    },
                },
                |_| Ok(()),
            )
            .await
            .unwrap();
        let challenge = store
            .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
            .await
            .unwrap();
        let statement = WorkflowApprovalStatement {
            challenge,
            decision: WorkflowDecision::Approve,
            reason: "Reviewed".into(),
        };
        let key = DesktopWorkflowCredential::load_or_create(&runtime).unwrap();
        store
            .decide_workflow(
                key.verify(statement.clone(), &key.sign(&statement).unwrap())
                    .unwrap(),
                "desktop",
            )
            .await
            .unwrap();
        Self {
            _dir: dir,
            runtime,
            source,
            store,
            plan,
        }
    }

    pub async fn task_id(&self, logical: &str) -> String {
        sqlx::query_scalar(
            "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = ?",
        )
        .bind(&self.plan.run_id)
        .bind(logical)
        .fetch_one(self.store.pool())
        .await
        .unwrap()
    }

    pub async fn request(
        &self,
        logical: Option<&str>,
        retry: Option<&str>,
    ) -> Result<WorkflowWorkspaceRecord> {
        prepare(
            &self.store,
            &self.runtime,
            PrepareWorkflowWorkspace {
                request_id: Uuid::new_v4().to_string(),
                run_id: self.plan.run_id.clone(),
                revision: 1,
                task_id: match logical {
                    Some(logical) => Some(self.task_id(logical).await),
                    None => None,
                },
                retry_of: retry.map(str::to_string),
            },
        )
        .await
    }

    pub async fn integration(&self) -> WorkflowWorkspaceRecord {
        let record = self.request(None, None).await.unwrap();
        assert_eq!(record.phase, Phase::Ready, "{record:?}");
        record
    }

    pub async fn task(&self, logical: &str) -> WorkflowWorkspaceRecord {
        self.request(Some(logical), None).await.unwrap()
    }

    pub async fn reserve(&self, logical: &str) -> WorkflowWorkspaceRecord {
        let mut candidate = self.store.find_workspace("owner").await.unwrap().unwrap();
        candidate.id = Uuid::new_v4().to_string();
        candidate.instance_id = Uuid::new_v4().to_string();
        candidate.kind = WorkspaceKind::Linked;
        candidate.branch = Some(format!("alera/workflows/{}", candidate.id));
        candidate.path = self
            ._dir
            .path()
            .join(&candidate.id)
            .to_string_lossy()
            .into_owned();
        self.store
            .reserve_workflow_workspace(
                &PrepareWorkflowWorkspace {
                    request_id: Uuid::new_v4().to_string(),
                    run_id: self.plan.run_id.clone(),
                    revision: 1,
                    task_id: Some(self.task_id(logical).await),
                    retry_of: None,
                },
                candidate,
            )
            .await
            .unwrap()
    }
}
