use serde_json::Value;
use sqlx::sqlite::{SqliteConnectOptions,SqlitePoolOptions};
use sqlx::Row as _;

#[derive(Clone,Default)]
pub(crate) struct WorkbenchPrefsStore {
    #[cfg(all(test,feature="gpui-tests"))]
    memory:Option<std::sync::Arc<std::sync::Mutex<Option<Value>>>>,
    #[cfg(all(test,feature="gpui-tests"))]
    write_gate:Option<async_channel::Receiver<()>>,
}

impl WorkbenchPrefsStore {
    #[cfg(all(test,feature="gpui-tests"))]
    pub(crate) fn memory(value:Option<Value>)->Self {Self{memory:Some(std::sync::Arc::new(std::sync::Mutex::new(value))),write_gate:None}}

    #[cfg(all(test,feature="gpui-tests"))]
    pub(crate) fn gated_memory(value:Option<Value>,gate:async_channel::Receiver<()>)->Self {
        let mut store=Self::memory(value);store.write_gate=Some(gate);store
    }

    pub(crate) async fn load(&self)->Option<Value> {
        #[cfg(all(test,feature="gpui-tests"))]
        if let Some(value)=&self.memory {return value.lock().ok()?.clone();}
        load_local_workbench_prefs().await
    }

    pub(crate) async fn save(&self,prefs:&Value)->Option<()> {
        #[cfg(all(test,feature="gpui-tests"))]
        if let Some(gate)=&self.write_gate {gate.recv().await.ok()?;}
        #[cfg(all(test,feature="gpui-tests"))]
        if let Some(value)=&self.memory {*value.lock().ok()?=Some(prefs.clone());return Some(());}
        save_local_workbench_prefs(prefs).await
    }
}

async fn load_local_workbench_prefs()->Option<Value> {
    let path=crate::local_database_path()?;
    let (sender,receiver)=async_channel::bounded(1);
    std::thread::spawn(move||{
        let value=local_database_runtime().and_then(|runtime|runtime.block_on(async{
            let pool=open_local_database(path).await?;
            load_from_pool(&pool).await
        }));
        let _=sender.send_blocking(value);
    });
    receiver.recv().await.ok().flatten()
}

async fn load_from_pool(pool:&sqlx::SqlitePool)->Option<Value> {
    let mut prefs=read_prefs(pool).await?;
    if prefs.get("gitDiffViewMode").and_then(Value::as_str)==Some("list") {
        // Repair only the legacy enum field in the latest row. Replacing the
        // whole earlier snapshot would overwrite concurrent Flutter changes.
        let migrated=repair_legacy_source_control_mode(pool).await;
        match migrated {
            Ok(_)=>prefs=read_prefs(pool).await?,
            Err(error)=>{
                crate::app_log::warning("workbench_view_prefs",&format!("Could not migrate legacy Source Control preference: {error}"));
                prefs["gitDiffViewMode"]=Value::String("flat".into());
            }
        }
    }
    Some(prefs)
}

async fn repair_legacy_source_control_mode(pool:&sqlx::SqlitePool)->Result<(),sqlx::Error> {
    sqlx::query("UPDATE workbench_view_prefs_table SET data_json=json_set(data_json,'$.gitDiffViewMode','flat') WHERE id=1 AND CASE WHEN json_valid(data_json) THEN json_extract(data_json,'$.gitDiffViewMode')='list' ELSE 0 END")
        .execute(pool).await?;
    Ok(())
}

async fn read_prefs(pool:&sqlx::SqlitePool)->Option<Value> {
    let row=sqlx::query("SELECT data_json FROM workbench_view_prefs_table WHERE id=1").fetch_optional(pool).await.ok()??;
    serde_json::from_str(row.get::<&str,_>("data_json")).ok()
}

async fn save_local_workbench_prefs(prefs:&Value)->Option<()> {
    let path=crate::local_database_path()?;
    let encoded=serde_json::to_string(prefs).ok()?;
    let (sender,receiver)=async_channel::bounded(1);
    std::thread::spawn(move||{
        let value=local_database_runtime().and_then(|runtime|runtime.block_on(async{
            let pool=open_local_database(path).await?;
            sqlx::query("INSERT INTO workbench_view_prefs_table (id,data_json) VALUES (1,?) ON CONFLICT(id) DO UPDATE SET data_json=excluded.data_json")
                .bind(encoded).execute(&pool).await.ok()?;
            Some(())
        }));
        let _=sender.send_blocking(value);
    });
    receiver.recv().await.ok().flatten()
}

async fn open_local_database(path:std::path::PathBuf)->Option<sqlx::SqlitePool> {
    if !path.is_file(){return None;}
    let options=SqliteConnectOptions::new().filename(path).create_if_missing(false);
    SqlitePoolOptions::new().max_connections(1).connect_with(options).await.ok()
}

fn local_database_runtime()->Option<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread().enable_all().build().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn workbench_prefs_legacy_mode_migration_preserves_every_other_field() {
        let pool=SqlitePoolOptions::new().max_connections(1).connect("sqlite::memory:").await.unwrap();
        sqlx::query("CREATE TABLE workbench_view_prefs_table (id INTEGER PRIMARY KEY,data_json TEXT NOT NULL)").execute(&pool).await.unwrap();
        let mut expected:Value=serde_json::from_str(include_str!("../tests/fixtures/workbench_view_prefs.json")).unwrap();
        expected["futureClientField"]=json!({"preserve":["α","value"]});
        let mut legacy=expected.clone();legacy["gitDiffViewMode"]=json!("list");
        sqlx::query("INSERT INTO workbench_view_prefs_table VALUES (1,?)").bind(legacy.to_string()).execute(&pool).await.unwrap();
        assert_eq!(load_from_pool(&pool).await.unwrap(),expected);
        assert_eq!(read_prefs(&pool).await.unwrap(),expected);
        assert_eq!(load_from_pool(&pool).await.unwrap(),expected);
        pool.close().await;
    }

    #[tokio::test]
    async fn workbench_prefs_migration_preserves_concurrent_field_and_mode_changes() {
        let pool=SqlitePoolOptions::new().max_connections(1).connect("sqlite::memory:").await.unwrap();
        sqlx::query("CREATE TABLE workbench_view_prefs_table (id INTEGER PRIMARY KEY,data_json TEXT NOT NULL)").execute(&pool).await.unwrap();
        sqlx::query("INSERT INTO workbench_view_prefs_table VALUES (1,?)").bind(json!({"gitDiffViewMode":"list","sidebarWidth":300}).to_string()).execute(&pool).await.unwrap();
        let old=read_prefs(&pool).await.unwrap();
        sqlx::query("UPDATE workbench_view_prefs_table SET data_json=json_set(data_json,'$.sidebarWidth',412)").execute(&pool).await.unwrap();
        repair_legacy_source_control_mode(&pool).await.unwrap();
        assert_eq!(old["sidebarWidth"],300);
        assert_eq!(read_prefs(&pool).await.unwrap(),json!({"gitDiffViewMode":"flat","sidebarWidth":412}));
        sqlx::query("UPDATE workbench_view_prefs_table SET data_json=json_set(data_json,'$.gitDiffViewMode','tree')").execute(&pool).await.unwrap();
        repair_legacy_source_control_mode(&pool).await.unwrap();
        assert_eq!(read_prefs(&pool).await.unwrap()["gitDiffViewMode"],"tree");
        pool.close().await;
    }
}
