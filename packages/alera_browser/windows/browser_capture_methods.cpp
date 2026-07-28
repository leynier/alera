#include "alera_browser_plugin.h"

#include "browser_page.h"
#include "browser_value.h"

#include <Shlwapi.h>
#include <wincrypt.h>
#include <wrl.h>
#include <wrl/client.h>

#include <cmath>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace alera_browser {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

EncodableValue ArtifactValue(
    const std::filesystem::path& path,
    const std::string& mime) {
  return EncodableValue(EncodableMap{
      {EncodableValue("path"), EncodableValue(Utf8(path.wstring()))},
      {EncodableValue("mimeType"), EncodableValue(mime)},
      {EncodableValue("sizeBytes"), EncodableValue(FileSize(path))},
      {EncodableValue("suggestedFileName"),
       EncodableValue(FileName(path))}});
}

std::optional<std::string> JsonDataField(const std::string& json) {
  const auto key = json.find("\"data\"");
  const auto colon =
      key == std::string::npos ? key : json.find(':', key + 6);
  const auto quote =
      colon == std::string::npos ? colon : json.find('"', colon + 1);
  if (quote == std::string::npos) {
    return std::nullopt;
  }
  const auto end = json.find('"', quote + 1);
  if (end == std::string::npos) {
    return std::nullopt;
  }
  return json.substr(quote + 1, end - quote - 1);
}

bool WriteBase64(
    const std::filesystem::path& path,
    const std::string& encoded) {
  DWORD size = 0;
  if (!CryptStringToBinaryA(
          encoded.c_str(), static_cast<DWORD>(encoded.size()),
          CRYPT_STRING_BASE64, nullptr, &size, nullptr, nullptr) ||
      size == 0) {
    return false;
  }
  std::vector<BYTE> bytes(size);
  if (!CryptStringToBinaryA(
          encoded.c_str(), static_cast<DWORD>(encoded.size()),
          CRYPT_STRING_BASE64, bytes.data(), &size, nullptr, nullptr)) {
    return false;
  }
  const HANDLE file = CreateFileW(
      path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD written = 0;
  const bool succeeded =
      WriteFile(file, bytes.data(), size, &written, nullptr) &&
      written == size && FlushFileBuffers(file);
  CloseHandle(file);
  if (!succeeded) {
    DeleteFileW(path.c_str());
  }
  return succeeded;
}

std::optional<std::filesystem::path> TemporarySibling(
    const std::filesystem::path& destination) {
  GUID identifier = {};
  if (FAILED(CoCreateGuid(&identifier))) {
    return std::nullopt;
  }
  wchar_t encoded[39] = {};
  if (StringFromGUID2(identifier, encoded, 39) <= 0) {
    return std::nullopt;
  }
  return destination.parent_path() /
         (destination.filename().wstring() + L".alera-" + encoded +
          L".tmp");
}

void CaptureViewport(
    const std::shared_ptr<BrowserPage>& page,
    const std::filesystem::path& path,
    const std::shared_ptr<MethodResult>& result) {
  ComPtr<IStream> stream;
  const HRESULT opened = SHCreateStreamOnFileEx(
      path.c_str(), STGM_WRITE | STGM_SHARE_EXCLUSIVE,
      FILE_ATTRIBUTE_NORMAL, TRUE, nullptr, &stream);
  if (FAILED(opened)) {
    result->Error("capture_failed", HResultMessage(opened));
    return;
  }
  const HRESULT started = page->webview()->CapturePreview(
      COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
      Callback<ICoreWebView2CapturePreviewCompletedHandler>(
          [stream, path, result](HRESULT captured) mutable {
            const HRESULT committed = stream->Commit(STGC_DEFAULT);
            stream.Reset();
            if (FAILED(captured) || FAILED(committed) ||
                FileSize(path) <= 0) {
              DeleteFileW(path.c_str());
              result->Error(
                  "capture_failed",
                  FAILED(captured)
                      ? HResultMessage(captured)
                      : FAILED(committed)
                            ? HResultMessage(committed)
                            : "WebView2 wrote an empty screenshot.");
            } else {
              result->Success(ArtifactValue(path, "image/png"));
            }
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    stream.Reset();
    DeleteFileW(path.c_str());
    result->Error("capture_failed", HResultMessage(started));
  }
}

void CaptureFullPage(
    const std::shared_ptr<BrowserPage>& page,
    const std::filesystem::path& path,
    const std::shared_ptr<MethodResult>& result) {
  const HRESULT started = page->webview()->CallDevToolsProtocolMethod(
      L"Page.captureScreenshot",
      L"{\"format\":\"png\",\"fromSurface\":true,"
      L"\"captureBeyondViewport\":true}",
      Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
          [path, result](HRESULT captured, LPCWSTR raw) {
            const auto data =
                SUCCEEDED(captured) ? JsonDataField(Utf8(raw))
                                    : std::nullopt;
            if (FAILED(captured) || !data.has_value() ||
                !WriteBase64(path, *data) || FileSize(path) <= 0) {
              result->Error(
                  "capture_failed",
                  FAILED(captured)
                      ? HResultMessage(captured)
                      : "WebView2 returned invalid screenshot data.");
            } else {
              result->Success(ArtifactValue(path, "image/png"));
            }
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    result->Error("capture_failed", HResultMessage(started));
  }
}

void PrintPdf(
    const std::shared_ptr<BrowserPage>& page,
    const std::filesystem::path& path,
    bool landscape,
    bool print_background,
    const std::shared_ptr<MethodResult>& result) {
  const auto temporary = TemporarySibling(path);
  if (!temporary.has_value()) {
    result->Error(
        "pdf_failed", "Could not reserve a temporary PDF destination.");
    return;
  }
  ComPtr<ICoreWebView2_7> webview7;
  ComPtr<ICoreWebView2Environment6> environment6;
  ComPtr<ICoreWebView2PrintSettings> settings;
  HRESULT value =
      page->webview()->QueryInterface(IID_PPV_ARGS(&webview7));
  if (SUCCEEDED(value)) {
    value = page->environment()->QueryInterface(
        IID_PPV_ARGS(&environment6));
  }
  if (SUCCEEDED(value)) {
    value = environment6->CreatePrintSettings(&settings);
  }
  if (SUCCEEDED(value)) {
    value = settings->put_Orientation(
        landscape ? COREWEBVIEW2_PRINT_ORIENTATION_LANDSCAPE
                  : COREWEBVIEW2_PRINT_ORIENTATION_PORTRAIT);
  }
  if (SUCCEEDED(value)) {
    value = settings->put_ShouldPrintBackgrounds(
        print_background ? TRUE : FALSE);
  }
  if (FAILED(value)) {
    result->Error("pdf_failed", HResultMessage(value));
    return;
  }
  const HRESULT started = webview7->PrintToPdf(
      temporary->c_str(), settings.Get(),
      Callback<ICoreWebView2PrintToPdfCompletedHandler>(
          [temporary = *temporary, path, result](
              HRESULT printed, BOOL succeeded) {
            if (FAILED(printed) || !succeeded ||
                FileSize(temporary) <= 0) {
              DeleteFileW(temporary.c_str());
              result->Error(
                  "pdf_failed",
                  FAILED(printed) ? HResultMessage(printed)
                                  : "WebView2 wrote an empty PDF.");
            } else if (!MoveFileW(
                           temporary.c_str(), path.c_str())) {
              const DWORD error = GetLastError();
              DeleteFileW(temporary.c_str());
              result->Error(
                  error == ERROR_FILE_EXISTS ||
                          error == ERROR_ALREADY_EXISTS
                      ? "destination_exists"
                      : "pdf_failed",
                  error == ERROR_FILE_EXISTS ||
                          error == ERROR_ALREADY_EXISTS
                      ? "The PDF destination already exists."
                      : HResultMessage(HRESULT_FROM_WIN32(error)));
            } else {
              result->Success(
                  ArtifactValue(path, "application/pdf"));
            }
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    DeleteFileW(temporary->c_str());
    result->Error("pdf_failed", HResultMessage(started));
  }
}

}  // namespace

bool HandleBrowserCaptureMethod(
    AleraBrowserPlugin* plugin,
    const std::string& method,
    const EncodableMap& arguments,
    MethodResultPtr result) {
  const auto page_id = StringValue(arguments, "pageId");
  const auto page =
      page_id.has_value() ? plugin->FindPage(*page_id) : nullptr;
  const auto destination = StringValue(arguments, "destinationPath");
  if (!page) {
    Error(
        std::move(result), "page_not_found",
        "The browser page does not exist.");
    return true;
  }
  if (!destination.has_value() ||
      !IsAbsoluteFilePath(*destination)) {
    Error(
        std::move(result), "invalid_destination",
        "Browser artifacts require an absolute destination path.");
    return true;
  }
  if (std::abs(DoubleValue(arguments, "scale", 1) - 1.0) >
      0.000001) {
    Error(
        std::move(result), "unsupported_scale",
        "Windows screenshots currently support scale 1 only.");
    return true;
  }
  const std::filesystem::path path(Utf16(*destination));
  auto shared_result =
      std::shared_ptr<MethodResult>(std::move(result));
  if (method == "capture.screenshot") {
    if (BoolValue(arguments, "fullPage")) {
      CaptureFullPage(page, path, shared_result);
    } else {
      CaptureViewport(page, path, shared_result);
    }
  } else if (method == "capture.pdf") {
    PrintPdf(
        page, path, BoolValue(arguments, "landscape"),
        BoolValue(arguments, "printBackground", true), shared_result);
  } else {
    shared_result->NotImplemented();
    return false;
  }
  return true;
}

}  // namespace alera_browser
