//! The page count of a PDF, read without decoding any stream, as T3 Code's
//! `estimateClaudePdfPages`. Only an explicit, uncompressed page tree whose
//! `/Count` agrees with the visible page objects is counted; anything else,
//! including encrypted, incremental or object-stream files, is unknown.

const MAX_PDF_BYTES: usize = 20 * 1024 * 1024;
const MAX_TOKEN_BYTES: usize = 64;

fn delimiter(byte: u8) -> bool {
    byte <= 32 || b"()<>[]{}/%".contains(&byte)
}

fn find(bytes: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    bytes
        .get(from..)?
        .windows(needle.len())
        .position(|window| window == needle)
        .map(|position| from + position)
}

fn skip_line(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() && bytes[i] != b'\n' && bytes[i] != b'\r' {
        i += 1;
    }
    i
}

/// A `/Count` value: 1 to 999,999,999 without a leading zero.
fn page_count(token: &str) -> Option<u32> {
    let valid = (1..=9).contains(&token.len())
        && token.bytes().all(|byte| byte.is_ascii_digit())
        && !token.starts_with('0');
    valid.then(|| token.parse().ok()).flatten()
}

pub(super) fn estimate_pdf_pages(bytes: &[u8]) -> Option<u32> {
    if bytes.len() > MAX_PDF_BYTES || !bytes.starts_with(b"%PDF-") {
        return None;
    }
    let tail = &bytes[bytes.len().saturating_sub(1024)..];
    find(tail, b"%%EOF", 0)?;
    let (mut pages, mut count) = (0_u32, 0_u32);
    let (mut catalog, mut page_tree) = (false, false);
    let mut previous = String::new();
    let mut i = 0;
    while i < bytes.len() {
        let byte = bytes[i];
        if byte == b'%' {
            i = skip_line(bytes, i);
            continue;
        }
        if byte <= 32 {
            i += 1;
            continue;
        }
        if previous == "/Type" && byte != b'/' {
            return None;
        }
        if previous == "/Kids" {
            if byte != b'[' {
                return None;
            }
            previous.clear();
        }
        if byte == b'(' {
            let mut depth = 1;
            i += 1;
            while i < bytes.len() && depth > 0 {
                match bytes[i] {
                    b'\\' => i += 1,
                    b'(' => depth += 1,
                    b')' => depth -= 1,
                    _ => {}
                }
                i += 1;
            }
            if depth != 0 {
                return None;
            }
            previous.clear();
            continue;
        }
        if byte == b'<' && bytes.get(i + 1) != Some(&b'<') {
            i = find(bytes, b">", i + 1)? + 1;
            previous.clear();
            continue;
        }
        if byte == b'<' {
            i += 2;
            previous.clear();
            continue;
        }
        if delimiter(byte) && byte != b'/' {
            i += 1;
            continue;
        }
        let start = i;
        i += 1;
        while i < bytes.len() && !delimiter(bytes[i]) {
            i += 1;
        }
        if i - start > MAX_TOKEN_BYTES {
            return None;
        }
        let token: String = bytes[start..i].iter().map(|&byte| byte as char).collect();
        if token.contains('#')
            || ["/ObjStm", "/XRef", "/Encrypt", "/Prev"].contains(&token.as_str())
        {
            return None;
        }
        if token == "stream" {
            i = find(bytes, b"endstream", i)? + "endstream".len();
            previous.clear();
            continue;
        }
        if previous == "/Type" {
            match token.as_str() {
                "/Page" => pages += 1,
                "/Catalog" => catalog = true,
                "/Pages" => page_tree = true,
                _ => {}
            }
        }
        if previous == "/Count" {
            let value = page_count(&token)?;
            let mut next = i;
            while next < bytes.len() {
                if bytes[next] <= 32 {
                    next += 1;
                } else if bytes[next] == b'%' {
                    next = skip_line(bytes, next);
                } else {
                    break;
                }
            }
            // A second scalar is an indirect reference, not a page count.
            if next < bytes.len() && !delimiter(bytes[next]) {
                return None;
            }
            count = count.max(value);
        }
        previous = token;
    }
    (catalog && page_tree && pages > 0 && count == pages).then_some(pages)
}

#[cfg(test)]
mod tests {
    use super::estimate_pdf_pages as pages;

    const ONE_PAGE: &str = "%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Count 1 /Kids [3 0 R] >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R >> endobj\n%%EOF";

    pub(crate) fn pdf_with_pages(count: u32) -> String {
        let kids = (0..count)
            .map(|index| format!("{} 0 R", index + 3))
            .collect::<Vec<_>>()
            .join(" ");
        let mut pdf = format!(
            "%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Count {count} /Kids [{kids}] >> endobj\n"
        );
        for index in 0..count {
            pdf.push_str(&format!(
                "{} 0 obj << /Type /Page /Parent 2 0 R /Contents (page \\(x\\)) >> endobj\n",
                index + 3
            ));
        }
        pdf.push_str("%%EOF");
        pdf
    }

    #[test]
    fn explicit_page_trees_are_counted() {
        assert_eq!(pages(ONE_PAGE.as_bytes()), Some(1));
        assert_eq!(pages(pdf_with_pages(60).as_bytes()), Some(60));
        assert_eq!(pages(pdf_with_pages(100).as_bytes()), Some(100));
    }

    #[test]
    fn anything_unclear_is_unknown() {
        for pdf in [
            ONE_PAGE.replace("%%EOF", ""),
            ONE_PAGE.replace("endobj\n3", "(unfinished\n3"),
            ONE_PAGE.replace("/Pages 2 0 R", "/Pa#67es 2 0 R"),
            ONE_PAGE.replace("/Parent 2 0 R", "/Prev 42"),
            ONE_PAGE.replace(
                "/Type /Page /Parent",
                "/Type /ObjStm stream x endstream /Parent",
            ),
            ONE_PAGE.replace("/Parent 2 0 R", "/Encrypt 9 0 R"),
            ONE_PAGE.replace("/Count 1 /Kids [3 0 R]", "/Count 0 /Kids [3 0 R]"),
            ONE_PAGE.replace("/Count 1 /Kids", "/Count 1 0 R /Kids"),
            ONE_PAGE.replace("/Type /Page /Parent", "/Type 5 0 R /Parent"),
            ONE_PAGE.replace("/Kids [3 0 R]", "/Kids 4 0 R"),
            "%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 42 >> endobj\n%%EOF".into(),
            "This is not a PDF".into(),
        ] {
            assert_eq!(pages(pdf.as_bytes()), None, "{pdf}");
        }
    }
}
