//! The order `String.prototype.localeCompare` gives skill names under the
//! CLDR root collation, for the ASCII names skills use: punctuation before
//! digits before letters, letters compared without case first and lower
//! case winning a tie. Other characters follow letters by code point.

use std::cmp::Ordering;

/// Root collation order of the ASCII punctuation and symbols.
const SYMBOLS: &str = "_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$";

fn primary(character: char) -> (u8, u32) {
    if character.is_whitespace() {
        return (0, character as u32);
    }
    if let Some(index) = SYMBOLS.find(character) {
        return (1, index as u32);
    }
    if character.is_ascii_digit() {
        return (2, character as u32);
    }
    if character.is_ascii_alphabetic() {
        return (3, character.to_ascii_lowercase() as u32);
    }
    (4, character as u32)
}

/// T3 Code sorts skill lists with `localeCompare`; adapters sort with this.
pub fn compare_skill_names(left: &str, right: &str) -> Ordering {
    left.chars()
        .map(primary)
        .cmp(right.chars().map(primary))
        .then_with(|| {
            // Lower case sorts before upper case at the first case difference.
            left.chars()
                .map(|character| character.is_ascii_uppercase())
                .cmp(
                    right
                        .chars()
                        .map(|character| character.is_ascii_uppercase()),
                )
        })
        .then_with(|| left.cmp(right))
}
