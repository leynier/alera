#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_profile.h"
#include "browser_value.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <memory>
#include <optional>

namespace alera_browser {
namespace {

std::shared_ptr<BrowserPage> RequiredPage(
    AleraBrowserPlugin* plugin,
    const EncodableMap& arguments,
    MethodResultPtr* result) {
  const auto id = StringValue(arguments, "pageId");
  const auto page = id.has_value() ? plugin->FindPage(*id) : nullptr;
  if (!page) {
    Error(
        std::move(*result), "page_not_found",
        "The browser page does not exist.");
  }
  return page;
}

bool SafeHeaderName(const std::string& value) {
  if (value.empty()) {
    return false;
  }
  constexpr char kSeparators[] = "()<>@,;:\\\"/[]?={} \t";
  return std::all_of(value.begin(), value.end(), [&](unsigned char item) {
    return item > 0x20 && item < 0x7f &&
           std::strchr(kSeparators, item) == nullptr;
  });
}

bool SafeHeaderValue(const std::string& value) {
  return std::none_of(value.begin(), value.end(), [](unsigned char item) {
    return (item < 0x20 && item != '\t') || item == 0x7f;
  });
}

std::optional<std::map<std::string, std::string>> Headers(
    const EncodableMap& arguments) {
  std::map<std::string, std::string> result;
  for (const auto& [key, value] : MapValue(arguments, "headers")) {
    const auto* name = std::get_if<std::string>(&key);
    const auto* text = std::get_if<std::string>(&value);
    if (name == nullptr || text == nullptr ||
        !SafeHeaderName(*name) || !SafeHeaderValue(*text)) {
      return std::nullopt;
    }
    result[*name] = *text;
  }
  return result;
}

}  // namespace

bool HandleBrowserPageMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result) {
  if (method == "page.create") {
    const auto profile_id =
        StringValue(arguments, "profileId").value_or("default");
    const auto profile = plugin->FindProfile(profile_id);
    if (!profile) {
      Error(
          std::move(result), "profile_not_found",
          "The browser profile does not exist.");
      return true;
    }
    auto id = StringValue(arguments, "id");
    if (!id.has_value()) {
      id = "page-" + std::to_string(plugin->next_page_id_++);
    }
    if (!IsValidBrowserId(*id) || plugin->FindPage(*id)) {
      Error(
          std::move(result), "invalid_page",
          "The page id is invalid or already exists.");
      return true;
    }
    const auto opener_id = StringValue(arguments, "openerPageId");
    if (opener_id.has_value()) {
      const auto opener = plugin->FindPage(*opener_id);
      if (!opener || opener->profile_id() != profile_id) {
        Error(
            std::move(result), "invalid_opener",
            "The popup opener must exist in the same profile.");
        return true;
      }
    }
    const auto initial_url = StringValue(arguments, "initialUrl");
    if (initial_url.has_value() && !IsAllowedBrowserUrl(*initial_url)) {
      Error(
          std::move(result), "invalid_url",
          "Only HTTP, HTTPS, and about:blank are allowed.");
      return true;
    }
    auto shared_result =
        std::shared_ptr<MethodResult>(std::move(result));
    const auto lifetime = plugin->lifetime();
    BrowserPage::Create(
        plugin, plugin->parent_window(), profile, *id, initial_url,
        StringValue(arguments, "userAgent"), opener_id,
        BoolValue(arguments, "transient"),
        [plugin, lifetime, shared_result](
            HRESULT created,
            std::shared_ptr<BrowserPage> page) {
          if (lifetime.expired()) {
            if (page) {
              page->Close();
            }
            return;
          }
          if (FAILED(created) || !page) {
            shared_result->Error(
                "page_create_failed", HResultMessage(created));
            return;
          }
          if (!plugin->AddPage(page)) {
            page->Close();
            shared_result->Error(
                "duplicate_page", "The browser page already exists.");
            return;
          }
          shared_result->Success(EncodableValue(EncodableMap{
              {EncodableValue("id"), EncodableValue(page->id())},
              {EncodableValue("title"), EncodableValue("")}}));
        });
    return true;
  }

  const auto id = StringValue(arguments, "pageId");
  if (method == "page.close") {
    if (id.has_value()) {
      plugin->RemovePage(*id);
    }
    Success(std::move(result));
    return true;
  }
  auto page = RequiredPage(plugin, arguments, &result);
  if (!page) {
    return true;
  }

  if (method == "page.attach" || method == "page.detach") {
    page->SetAttached(method == "page.attach");
    Success(std::move(result));
  } else if (method == "page.setObscured") {
    page->SetObscured(BoolValue(arguments, "obscured"));
    Success(std::move(result));
  } else if (method == "page.setBounds") {
    page->SetBounds(
        DoubleValue(arguments, "x"), DoubleValue(arguments, "y"),
        DoubleValue(arguments, "width"),
        DoubleValue(arguments, "height"),
        DoubleValue(arguments, "scale", 1));
    Success(std::move(result));
  } else if (method == "page.adoptTransient") {
    const auto profile_id = StringValue(arguments, "profileId");
    if (!page->transient() || !profile_id.has_value() ||
        page->profile_id() != *profile_id) {
      Error(
          std::move(result), "invalid_transient_page",
          "The transient popup does not match the requested profile.");
    } else {
      page->SetAdopted(true);
      Success(std::move(result));
    }
  } else if (method == "page.promoteTransient") {
    if (!page->transient() || !page->adopted()) {
      Error(
          std::move(result), "invalid_transient_page",
          "The transient popup must be adopted before promotion.");
    } else {
      page->Promote();
      Success(std::move(result));
    }
  } else if (method == "page.currentUrl") {
    const auto value = page->CurrentUrl();
    Success(
        std::move(result),
        value.has_value() ? EncodableValue(*value) : EncodableValue());
  } else if (method == "page.title") {
    const auto value = page->Title();
    Success(
        std::move(result),
        value.has_value() ? EncodableValue(*value) : EncodableValue());
  } else if (method == "page.canGoBack") {
    Success(std::move(result), EncodableValue(page->CanGoBack()));
  } else if (method == "page.canGoForward") {
    Success(std::move(result), EncodableValue(page->CanGoForward()));
  } else if (
      method == "page.goBack" || method == "page.goForward" ||
      method == "page.reload" || method == "page.stop") {
    const HRESULT operation =
        method == "page.goBack"       ? page->GoBack()
        : method == "page.goForward" ? page->GoForward()
        : method == "page.reload"    ? page->Reload()
                                      : page->Stop();
    if (FAILED(operation)) {
      Error(
          std::move(result), "navigation_failed",
          HResultMessage(operation));
    } else {
      Success(std::move(result));
    }
  } else if (method == "page.loadUrl") {
    const auto url = StringValue(arguments, "url");
    const auto headers = Headers(arguments);
    if (!url.has_value() || !IsAllowedBrowserUrl(*url)) {
      Error(
          std::move(result), "invalid_url",
          "Only HTTP, HTTPS, and about:blank are allowed.");
      return true;
    }
    if (!headers.has_value()) {
      Error(
          std::move(result), "invalid_headers",
          "Navigation headers contain invalid characters.");
      return true;
    }
    auto shared_result =
        std::shared_ptr<MethodResult>(std::move(result));
    page->Navigate(*url, *headers, [shared_result](HRESULT value) {
      if (FAILED(value)) {
        shared_result->Error("navigation_failed", HResultMessage(value));
      } else {
        shared_result->Success();
      }
    });
  } else if (method == "page.evaluateJavaScript") {
    const auto script = StringValue(arguments, "script");
    if (!script.has_value()) {
      Error(
          std::move(result), "invalid_script",
          "A JavaScript expression is required.");
      return true;
    }
    auto shared_result =
        std::shared_ptr<MethodResult>(std::move(result));
    page->ExecuteScript(
        *script, [shared_result](HRESULT value, std::string json) {
          if (FAILED(value)) {
            shared_result->Error(
                "javascript_failed", HResultMessage(value));
          } else {
            shared_result->Success(EncodableValue(std::move(json)));
          }
        });
  } else if (method == "page.upload") {
    Error(
        std::move(result), "unsupported_upload",
        "Native file upload is not advertised by this backend.");
  } else {
    result->NotImplemented();
    return false;
  }
  return true;
}

}  // namespace alera_browser
