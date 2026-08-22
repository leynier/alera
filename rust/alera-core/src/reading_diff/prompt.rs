// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

pub const SCHEMA_VERSION: u32 = 1;
pub const RUBRIC_VERSION: &str = "alera-reading-diff-rubric-v7";

pub fn plan_schema() -> String {
    format!(
        r##"{{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{{"version":{{"type":"integer","const":{SCHEMA_VERSION}}},"remove":{{"type":"array","items":{{"$ref":"#/$defs/range"}}}},"replace":{{"type":"array","items":{{"type":"object","additionalProperties":false,"properties":{{"line":{{"type":"integer","minimum":1}},"old":{{"type":"string"}},"new":{{"type":"string"}}}},"required":["line","old","new"]}}}},"fold":{{"type":"array","items":{{"$ref":"#/$defs/range"}}}},"summary":{{"type":"string","minLength":1,"maxLength":500}}}},"required":["version","remove","replace","fold","summary"],"$defs":{{"range":{{"type":"object","additionalProperties":false,"properties":{{"start_line":{{"type":"integer","minimum":1}},"end_line":{{"type":"integer","minimum":1}}}},"required":["start_line","end_line"]}}}}}}"##
    )
}
