use std::cmp::Ordering;
use std::collections::BinaryHeap;

use super::super::WorkspaceQuickOpenMatch;
use super::index::{QuickOpenFile, QuickOpenIndex, SegmentMatch};

pub(super) fn search(
    index: &QuickOpenIndex,
    query: &str,
    limit: u32,
) -> Vec<WorkspaceQuickOpenMatch> {
    let limit = usize::try_from(limit).unwrap_or(usize::MAX);
    if limit == 0 {
        return Vec::new();
    }

    let normalized_query = query.trim().to_lowercase();
    let query_code_units = normalized_query.encode_utf16().collect::<Vec<_>>();
    if query_code_units.is_empty() {
        return index
            .files
            .iter()
            .take(limit)
            .map(|file| WorkspaceQuickOpenMatch {
                relative_path: file.relative_path.clone(),
                score: 0,
            })
            .collect();
    }

    let mut indexed_files = vec![false; index.files.len()];
    let mut ranked = Vec::with_capacity(limit.min(index.files.len()));
    let segment_node = index.segment_prefixes.lookup(&query_code_units);

    let mut path_index = first_path_at_least(&index.files, &normalized_query);
    while path_index < index.files.len()
        && index.files[path_index].normalized_path.as_str() == normalized_query
    {
        append_indexed_match(
            &index.files,
            &mut indexed_files,
            &mut ranked,
            path_index,
            100_000,
        );
        path_index += 1;
    }

    if let Some(node) = segment_node {
        append_segment_matches(
            &index.files,
            &mut indexed_files,
            &mut ranked,
            &node.exact_matches,
            90_000,
            limit,
        );
    }
    if ranked.len() == limit {
        return into_matches(ranked);
    }

    path_index = first_path_at_least(&index.files, &normalized_query);
    while path_index < index.files.len()
        && index.files[path_index]
            .normalized_path
            .starts_with(&normalized_query)
    {
        append_indexed_match(
            &index.files,
            &mut indexed_files,
            &mut ranked,
            path_index,
            80_000,
        );
        if ranked.len() == limit {
            return into_matches(ranked);
        }
        path_index += 1;
    }

    if let Some(node) = segment_node {
        append_segment_matches(
            &index.files,
            &mut indexed_files,
            &mut ranked,
            &node.prefix_matches,
            70_000,
            limit,
        );
    }
    if ranked.len() == limit {
        return into_matches(ranked);
    }

    let lower_matches = search_lower(
        index,
        &indexed_files,
        &normalized_query,
        &query_code_units,
        limit - ranked.len(),
    );
    ranked.extend(lower_matches);
    into_matches(ranked)
}

fn append_indexed_match<'a>(
    files: &'a [QuickOpenFile],
    indexed_files: &mut [bool],
    ranked: &mut Vec<RankedFile<'a>>,
    file_index: usize,
    score: i32,
) {
    if !indexed_files[file_index] {
        indexed_files[file_index] = true;
        ranked.push(RankedFile {
            file: &files[file_index],
            score,
        });
    }
}

fn append_segment_matches<'a>(
    files: &'a [QuickOpenFile],
    indexed_files: &mut [bool],
    ranked: &mut Vec<RankedFile<'a>>,
    matches: &[SegmentMatch],
    base_score: i32,
    limit: usize,
) {
    for matching_segment in matches {
        append_indexed_match(
            files,
            indexed_files,
            ranked,
            matching_segment.file_index,
            base_score - matching_segment.segment_index as i32,
        );
        if ranked.len() == limit {
            break;
        }
    }
}

fn first_path_at_least(files: &[QuickOpenFile], query: &str) -> usize {
    let mut low = 0;
    let mut high = files.len();
    while low < high {
        let middle = low + (high - low) / 2;
        if files[middle].normalized_path.as_str() < query {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    low
}

fn search_lower<'a>(
    index: &'a QuickOpenIndex,
    indexed_files: &[bool],
    query: &str,
    query_code_units: &[u16],
    limit: usize,
) -> Vec<RankedFile<'a>> {
    let query_character_counts = character_counts(query_code_units);
    let Some(candidates) = index.character_index.candidates(&query_character_counts) else {
        return Vec::new();
    };
    let mut best: BinaryHeap<RankedFile<'a>> = BinaryHeap::with_capacity(limit);
    for candidate in candidates {
        let file_index = candidate.file_index;
        let file = &index.files[file_index];
        if indexed_files[file_index] || !has_required_characters(file, &query_character_counts) {
            continue;
        }
        let minimum_score = (best.len() == limit).then(|| {
            best.peek()
                .expect("full result heap has a worst match")
                .score
        });
        let Some(score) = lower_score(file, query, query_code_units, minimum_score) else {
            continue;
        };
        if minimum_score.is_some_and(|minimum| score <= minimum) {
            continue;
        }
        let candidate = RankedFile { file, score };
        if best.len() < limit {
            best.push(candidate);
        } else if candidate < *best.peek().expect("non-empty result heap") {
            best.pop();
            best.push(candidate);
        }
    }
    let mut ranked = best.into_vec();
    ranked.sort_by(compare_best);
    ranked
}

fn into_matches(ranked: Vec<RankedFile<'_>>) -> Vec<WorkspaceQuickOpenMatch> {
    ranked
        .into_iter()
        .map(|candidate| WorkspaceQuickOpenMatch {
            relative_path: candidate.file.relative_path.clone(),
            score: candidate.score,
        })
        .collect()
}

fn character_counts(code_units: &[u16]) -> Vec<(u16, u8)> {
    let mut counts: Vec<(u16, u8)> = Vec::new();
    for &code_unit in code_units {
        match counts.binary_search_by_key(&code_unit, |(unit, _)| *unit) {
            Ok(index) => counts[index].1 = counts[index].1.saturating_add(1),
            Err(index) => counts.insert(index, (code_unit, 1)),
        }
    }
    counts
}

fn has_required_characters(file: &QuickOpenFile, query: &[(u16, u8)]) -> bool {
    query.iter().all(|(query_unit, query_count)| {
        file.normalized_character_counts
            .binary_search_by_key(query_unit, |(unit, _)| *unit)
            .is_ok_and(|index| file.normalized_character_counts[index].1 >= *query_count)
    })
}

struct RankedFile<'a> {
    file: &'a QuickOpenFile,
    score: i32,
}

impl PartialEq for RankedFile<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.score == other.score
            && self.file.normalized_path == other.file.normalized_path
            && self.file.relative_path == other.file.relative_path
    }
}

impl Eq for RankedFile<'_> {}

impl Ord for RankedFile<'_> {
    fn cmp(&self, other: &Self) -> Ordering {
        other
            .score
            .cmp(&self.score)
            .then_with(|| self.file.normalized_path.cmp(&other.file.normalized_path))
            .then_with(|| self.file.relative_path.cmp(&other.file.relative_path))
    }
}

impl PartialOrd for RankedFile<'_> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn compare_best(left: &RankedFile<'_>, right: &RankedFile<'_>) -> Ordering {
    right
        .score
        .cmp(&left.score)
        .then_with(|| left.file.normalized_path.cmp(&right.file.normalized_path))
        .then_with(|| left.file.relative_path.cmp(&right.file.relative_path))
}

fn lower_score(
    file: &QuickOpenFile,
    query: &str,
    query_code_units: &[u16],
    minimum_score: Option<i32>,
) -> Option<i32> {
    if let Some(index) = find_code_units(&file.normalized_code_units, query_code_units) {
        let substring_score = 60_000 - index as i32;
        if score_if_eligible(substring_score, minimum_score).is_some()
            || minimum_score.is_none()
            || fuzzy_upper_bound(query_code_units.len()) < minimum_score.unwrap_or_default()
        {
            return score_if_eligible(substring_score, minimum_score);
        }
    }
    if minimum_score.is_some_and(|minimum| fuzzy_upper_bound(query_code_units.len()) < minimum) {
        return None;
    }
    let fuzzy_score = fuzzy_subsequence_score(&file.normalized_code_units, query_code_units)?;
    let file_name_has_prefix = file
        .normalized_segment_ranges
        .last()
        .is_some_and(|&(start, end)| file.normalized_path[start..end].starts_with(query));
    score_if_eligible(
        1_000 + fuzzy_score + if file_name_has_prefix { 100 } else { 0 },
        minimum_score,
    )
}

fn score_if_eligible(score: i32, minimum_score: Option<i32>) -> Option<i32> {
    minimum_score
        .is_none_or(|minimum| score >= minimum)
        .then_some(score)
}

fn fuzzy_upper_bound(query_length: usize) -> i32 {
    1_100i32.saturating_add((query_length as i32).saturating_mul(120))
}

fn find_code_units(candidate: &[u16], query: &[u16]) -> Option<usize> {
    if query.len() > candidate.len() {
        return None;
    }
    if query.is_empty() {
        return Some(0);
    }
    candidate
        .windows(query.len())
        .position(|window| window == query)
}

fn fuzzy_subsequence_score(candidate: &[u16], query: &[u16]) -> Option<i32> {
    let mut candidate_index = 0;
    let mut previous_match_index = None;
    let mut score = 0;
    for &query_character in query {
        let match_index = candidate
            .iter()
            .enumerate()
            .skip(candidate_index)
            .find_map(|(index, character)| (*character == query_character).then_some(index))?;
        if match_index == 0 || is_path_separator(candidate[match_index - 1]) {
            score += 100;
        }
        if match_index == candidate_index {
            score += 20;
        }
        if let Some(previous) = previous_match_index {
            score -= (match_index - previous - 1) as i32 * 5;
        }
        previous_match_index = Some(match_index);
        candidate_index = match_index + 1;
    }
    Some(score)
}

fn is_path_separator(code_unit: u16) -> bool {
    code_unit == b'/' as u16 || code_unit == b'\\' as u16
}
