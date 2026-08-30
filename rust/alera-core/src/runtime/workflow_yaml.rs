use anyhow::{anyhow, bail, Result};
use serde_json::{Map, Value};
use yaml_rust2::parser::{Event, Parser};
use yaml_rust2::scanner::TScalarStyle;

pub const WORKFLOW_DOCUMENT_MAX_BYTES: usize = 256 * 1024;
const MAX_NODES: usize = 8192;
const MAX_DEPTH: usize = 24;

enum Collection {
    Sequence(Vec<Value>),
    Mapping(Map<String, Value>, Option<String>),
}

/// Parse portable configuration without expanding aliases or constructing an
/// unbounded YAML tree. Call from a bounded blocking worker, never the host actor.
pub fn parse_workflow_yaml(source: &str) -> Result<Value> {
    if source.is_empty() || source.len() > WORKFLOW_DOCUMENT_MAX_BYTES || source.contains('\0') {
        bail!("workflow YAML is empty, too large or contains NUL");
    }
    let mut parser = Parser::new_from_str(source);
    let mut stack = Vec::new();
    let mut root = None;
    let mut documents = 0;
    let mut nodes = 0;
    loop {
        let (event, marker) = parser.next_token().map_err(|error| {
            anyhow!(
                "invalid workflow YAML at line {}, column {}",
                error.marker().line(),
                error.marker().col()
            )
        })?;
        let is_sequence = matches!(&event, Event::SequenceStart(..));
        let result = match event {
            Event::StreamStart | Event::DocumentEnd => Ok(()),
            Event::StreamEnd => break,
            Event::DocumentStart => {
                documents += 1;
                if documents != 1 {
                    bail!("workflow YAML must contain exactly one document");
                }
                Ok(())
            }
            Event::Alias(_) => bail!("workflow YAML aliases and anchors are not allowed"),
            Event::Scalar(text, style, anchor, tag) => {
                if anchor != 0 || tag.is_some() {
                    bail!("workflow YAML anchors and tags are not allowed");
                }
                count_node(&mut nodes, stack.len())?;
                let value = scalar(text, style);
                append(value, &mut stack, &mut root)
            }
            Event::SequenceStart(anchor, tag) | Event::MappingStart(anchor, tag) => {
                if anchor != 0 || tag.is_some() {
                    bail!("workflow YAML anchors and tags are not allowed");
                }
                count_node(&mut nodes, stack.len())?;
                if is_sequence {
                    stack.push(Collection::Sequence(Vec::new()));
                } else {
                    stack.push(Collection::Mapping(Map::new(), None));
                }
                Ok(())
            }
            Event::SequenceEnd | Event::MappingEnd => {
                let value = match stack.pop() {
                    Some(Collection::Sequence(values)) => Value::Array(values),
                    Some(Collection::Mapping(values, None)) => Value::Object(values),
                    _ => bail!("workflow YAML contains an incomplete collection"),
                };
                append(value, &mut stack, &mut root)
            }
            Event::Nothing => bail!("workflow YAML parser emitted an unexpected event"),
        };
        result.map_err(|error| {
            anyhow!("{error} at line {}, column {}", marker.line(), marker.col())
        })?;
    }
    if documents != 1 || !stack.is_empty() {
        bail!("workflow YAML must contain one complete document");
    }
    match root {
        Some(value @ Value::Object(_)) => Ok(value),
        _ => bail!("workflow YAML must have a mapping root"),
    }
}

fn count_node(nodes: &mut usize, depth: usize) -> Result<()> {
    *nodes += 1;
    if *nodes > MAX_NODES || depth >= MAX_DEPTH {
        bail!("workflow YAML exceeds the node or nesting limit");
    }
    Ok(())
}

fn append(value: Value, stack: &mut [Collection], root: &mut Option<Value>) -> Result<()> {
    match stack.last_mut() {
        Some(Collection::Sequence(items)) => items.push(value),
        Some(Collection::Mapping(items, key)) => match key.take() {
            Some(key) => {
                if items.insert(key, value).is_some() {
                    bail!("workflow YAML has a duplicate mapping key");
                }
            }
            None => {
                let Value::String(value) = value else {
                    bail!("workflow YAML mapping keys must be strings");
                };
                if value == "<<" {
                    bail!("workflow YAML merge keys are not allowed");
                }
                *key = Some(value);
            }
        },
        None if root.is_none() => *root = Some(value),
        None => bail!("workflow YAML contains multiple root values"),
    }
    Ok(())
}

fn scalar(text: String, style: TScalarStyle) -> Value {
    if style == TScalarStyle::Plain {
        match text.as_str() {
            "" | "~" | "null" => return Value::Null,
            "true" => return Value::Bool(true),
            "false" => return Value::Bool(false),
            _ => {}
        }
        if let Ok(number) = text.parse::<serde_json::Number>() {
            return Value::Number(number);
        }
    }
    Value::String(text)
}
