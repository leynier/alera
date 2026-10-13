use anyhow::{anyhow, Result};
use sqlx::SqliteConnection;

/// Installs a view or trigger whose definition may change between versions,
/// recreating it only when the stored definition differs. Every CLI command
/// opens the store next to a live runtime, and an unconditional drop and
/// create commits a schema change on each of those opens: that invalidates
/// the runtime's read snapshot, and its next deferred write fails with
/// SQLITE_BUSY_SNAPSHOT, which the busy timeout does not retry.
pub(super) async fn replace_schema_object(
    conn: &mut SqliteConnection,
    create_sql: &str,
) -> Result<()> {
    let wanted = SchemaObject::parse(create_sql)
        .ok_or_else(|| anyhow!("not a CREATE VIEW or CREATE TRIGGER statement"))?;
    let stored: Option<Option<String>> =
        sqlx::query_scalar("SELECT sql FROM sqlite_master WHERE type = ? AND name = ?")
            .bind(wanted.kind.to_ascii_lowercase())
            .bind(&wanted.name)
            .fetch_optional(&mut *conn)
            .await?;
    let current = stored
        .flatten()
        .and_then(|sql| SchemaObject::parse(&sql))
        .is_some_and(|stored| stored == wanted);
    if current {
        return Ok(());
    }
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP {} IF EXISTS \"{}\"",
        wanted.kind, wanted.name
    )))
    .execute(&mut *conn)
    .await?;
    sqlx::query(sqlx::AssertSqlSafe(create_sql))
        .execute(&mut *conn)
        .await?;
    Ok(())
}

/// A definition in the form SQLite compares by: it stores the statement
/// without `TEMP`, `IF NOT EXISTS`, leading whitespace or the final `;`, so
/// both sides drop those and collapse whitespace. A difference this misses
/// only costs a needless recreate.
#[derive(Debug, PartialEq)]
struct SchemaObject {
    kind: String,
    name: String,
    body: String,
}

impl SchemaObject {
    fn parse(sql: &str) -> Option<Self> {
        let mut tokens = sql.split_whitespace().peekable();
        if !tokens.next()?.eq_ignore_ascii_case("CREATE") {
            return None;
        }
        if tokens
            .peek()
            .is_some_and(|t| t.eq_ignore_ascii_case("TEMP") || t.eq_ignore_ascii_case("TEMPORARY"))
        {
            tokens.next();
        }
        let kind = tokens.next()?.to_ascii_uppercase();
        if kind != "VIEW" && kind != "TRIGGER" {
            return None;
        }
        let mut rest: Vec<&str> = tokens.collect();
        if rest.len() >= 3
            && rest[0].eq_ignore_ascii_case("IF")
            && rest[1].eq_ignore_ascii_case("NOT")
            && rest[2].eq_ignore_ascii_case("EXISTS")
        {
            rest.drain(..3);
        }
        let (name, body) = rest.split_first()?;
        let body = body.join(" ");
        Some(Self {
            kind,
            name: name.trim_matches('"').to_string(),
            body: body.trim_end_matches(';').trim_end().to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::SchemaObject;

    #[test]
    fn matches_the_form_sqlite_stores() {
        let wanted = SchemaObject::parse(
            "  CREATE TRIGGER IF NOT EXISTS guard\n     BEFORE INSERT ON t\n     BEGIN SELECT 1; END;",
        );
        let stored =
            SchemaObject::parse("CREATE TRIGGER guard BEFORE INSERT ON t\n BEGIN SELECT 1; END");
        assert!(wanted.is_some());
        assert_eq!(wanted, stored);
    }

    #[test]
    fn a_changed_body_differs() {
        assert_ne!(
            SchemaObject::parse("CREATE VIEW v AS SELECT 1"),
            SchemaObject::parse("CREATE VIEW v AS SELECT 2")
        );
    }

    #[test]
    fn rejects_other_statements() {
        assert_eq!(SchemaObject::parse("CREATE TABLE t (a)"), None);
        assert_eq!(SchemaObject::parse("DROP VIEW v"), None);
    }
}
