#include "browser_import_internal.h"

#include "browser_import_limits.h"
#include "browser_json.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>

namespace alera_browser {
namespace {

const BrowserJsonValue* FirstField(
    const BrowserJsonValue& object,
    std::initializer_list<const char*> names) {
  for (const auto* name : names) {
    const auto* value = object.Find(name);
    if (value != nullptr) {
      return value;
    }
  }
  return nullptr;
}

std::optional<std::string> StringField(
    const BrowserJsonValue& object,
    std::initializer_list<const char*> names) {
  const auto* value = FirstField(object, names);
  return value == nullptr ? std::nullopt : value->String();
}

bool BooleanField(
    const BrowserJsonValue& object,
    std::initializer_list<const char*> names,
    bool fallback = false) {
  const auto* value = FirstField(object, names);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto boolean = value->Boolean()) {
    return *boolean;
  }
  if (const auto number = value->Number()) {
    return *number != 0;
  }
  if (const auto string = value->String()) {
    auto normalized = *string;
    std::transform(
        normalized.begin(), normalized.end(), normalized.begin(),
        [](unsigned char character) {
          return static_cast<char>(std::tolower(character));
        });
    return normalized == "true" || normalized == "1";
  }
  return fallback;
}

std::optional<double> ExpirationMilliseconds(
    const BrowserJsonValue& object) {
  if (const auto* value = object.Find("expiresUtc")) {
    return value->Number();
  }
  if (const auto* value =
          FirstField(object, {"expirationDate", "expires"})) {
    const auto number = value->Number();
    if (!number.has_value()) {
      return std::nullopt;
    }
    return std::abs(*number) >= 10000000000.0
               ? *number
               : *number * 1000.0;
  }
  if (const auto* value = object.Find("expires_utc")) {
    const auto number = value->Number();
    if (number.has_value()) {
      return (*number - 11644473600000000.0) / 1000.0;
    }
  }
  return std::nullopt;
}

bool DecodeCookie(
    const BrowserJsonValue& value,
    BrowserCookieData* cookie,
    bool* expired) {
  if (value.kind != BrowserJsonValue::Kind::object) {
    return false;
  }
  const auto name = StringField(value, {"name"});
  const auto body = StringField(value, {"value"});
  const auto domain =
      StringField(value, {"domain", "host", "host_key"});
  const auto path = StringField(value, {"path"}).value_or("/");
  if (!name.has_value() || name->empty() || !body.has_value() ||
      !domain.has_value() || domain->empty() || path.empty() ||
      path.front() != '/') {
    return false;
  }
  cookie->name = *name;
  cookie->value = *body;
  cookie->domain = *domain;
  cookie->path = path;
  cookie->secure =
      BooleanField(value, {"secure", "isSecure", "is_secure"});
  cookie->http_only =
      BooleanField(value, {"httpOnly", "isHttpOnly", "is_httponly"});
  auto same_site =
      StringField(value, {"sameSite", "same_site"}).value_or("none");
  std::transform(
      same_site.begin(), same_site.end(), same_site.begin(),
      [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
      });
  if (same_site == "no_restriction") {
    same_site = "none";
  }
  if (same_site == "lax") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX;
  } else if (same_site == "strict") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_STRICT;
  } else if (same_site == "none" || same_site == "unspecified") {
    cookie->same_site = COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE;
  } else {
    return false;
  }
  const bool session = BooleanField(value, {"session"});
  const auto expiration = ExpirationMilliseconds(value);
  cookie->session = session || !expiration.has_value() ||
                    *expiration <= 0;
  if (!*cookie->session) {
    const double unix_seconds = *expiration / 1000.0;
    if (!std::isfinite(unix_seconds)) {
      return false;
    }
    const auto now = std::chrono::duration<double>(
                         std::chrono::system_clock::now()
                             .time_since_epoch())
                         .count();
    *expired = unix_seconds <= now;
    cookie->expires_unix_seconds = unix_seconds;
  }
  return true;
}

}  // namespace

BrowserImportBatch ParseManualBrowserCookieJson(
    const std::string& json) {
  BrowserImportBatch batch;
  if (!ManualCookieJsonWithinLimit(json.size())) {
    batch.outcome = "failed";
    batch.detail_code = "manual_json_too_large";
    return batch;
  }
  BrowserJsonValue root;
  if (!ParseBrowserJson(json, &root)) {
    batch.outcome = "failed";
    batch.detail_code = "manual_json_invalid";
    return batch;
  }
  const std::vector<BrowserJsonValue>* cookies = nullptr;
  if (root.kind == BrowserJsonValue::Kind::array) {
    cookies = &root.array;
  } else {
    const auto* nested = root.Find("cookies");
    if (nested != nullptr &&
        nested->kind == BrowserJsonValue::Kind::array) {
      cookies = &nested->array;
    }
  }
  if (cookies == nullptr ||
      cookies->size() > kManualCookieMaximumCount) {
    batch.outcome = "failed";
    batch.detail_code =
        cookies == nullptr ? "manual_json_invalid"
                           : "manual_json_too_many_cookies";
    return batch;
  }
  for (const auto& value : *cookies) {
    BrowserCookieData cookie;
    bool expired = false;
    if (!DecodeCookie(value, &cookie, &expired)) {
      batch.cookies.clear();
      batch.outcome = "failed";
      batch.detail_code = "manual_json_invalid_cookie";
      return batch;
    }
    if (expired) {
      ++batch.skipped;
    } else {
      batch.cookies.push_back(std::move(cookie));
    }
  }
  return DeduplicateBrowserImportBatch(std::move(batch));
}

}  // namespace alera_browser
