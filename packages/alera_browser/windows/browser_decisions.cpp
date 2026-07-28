#include "alera_browser_plugin.h"

#include "browser_decision_timeout.h"
#include "browser_page.h"
#include "browser_value.h"

#include <bcrypt.h>
#include <wincrypt.h>

#include <wrl/client.h>

#include <array>
#include <map>
#include <optional>
#include <sstream>
#include <utility>

namespace alera_browser {
using Microsoft::WRL::ComPtr;

namespace {

std::map<UINT_PTR, std::pair<AleraBrowserPlugin*, std::string>>
    g_decision_timers;

void CALLBACK DecisionTimeout(
    HWND,
    UINT,
    UINT_PTR timer_id,
    DWORD) {
  const auto iterator = g_decision_timers.find(timer_id);
  if (iterator == g_decision_timers.end()) {
    return;
  }
  auto [plugin, decision_id] = iterator->second;
  g_decision_timers.erase(iterator);
  KillTimer(nullptr, timer_id);
  plugin->ExpireDecision(decision_id);
}

std::string PermissionName(COREWEBVIEW2_PERMISSION_KIND kind) {
  switch (kind) {
    case COREWEBVIEW2_PERMISSION_KIND_MICROPHONE:
      return "microphone";
    case COREWEBVIEW2_PERMISSION_KIND_CAMERA:
      return "camera";
    case COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION:
      return "geolocation";
    case COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS:
      return "notifications";
    case COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS:
      return "sensors";
    case COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ:
      return "clipboardRead";
    default:
      return "unknown";
  }
}

struct CertificateDetails {
  std::string fingerprint;
  std::string subject;
  std::string issuer;
  int64_t valid_from_millis = 0;
  int64_t valid_to_millis = 0;
};

std::string Hex(const BYTE* bytes, DWORD length) {
  static constexpr char digits[] = "0123456789abcdef";
  std::string value;
  value.reserve(static_cast<size_t>(length) * 2);
  for (DWORD index = 0; index < length; ++index) {
    value.push_back(digits[bytes[index] >> 4]);
    value.push_back(digits[bytes[index] & 0x0f]);
  }
  return value;
}

std::optional<CertificateDetails> InspectCertificate(
    ICoreWebView2Certificate* certificate,
    const std::string& host) {
  if (certificate == nullptr || host.empty()) {
    return std::nullopt;
  }
  LPWSTR raw_pem = nullptr;
  LPWSTR raw_subject = nullptr;
  LPWSTR raw_issuer = nullptr;
  double valid_from = 0;
  double valid_to = 0;
  if (FAILED(certificate->ToPemEncoding(&raw_pem)) ||
      raw_pem == nullptr ||
      FAILED(certificate->get_Subject(&raw_subject)) ||
      FAILED(certificate->get_Issuer(&raw_issuer)) ||
      FAILED(certificate->get_ValidFrom(&valid_from)) ||
      FAILED(certificate->get_ValidTo(&valid_to))) {
    CoTaskMemFree(raw_pem);
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  DWORD der_size = 0;
  if (!CryptStringToBinaryW(
          raw_pem, 0, CRYPT_STRING_BASE64HEADER, nullptr, &der_size,
          nullptr, nullptr)) {
    CoTaskMemFree(raw_pem);
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  std::vector<BYTE> der(der_size);
  const bool decoded = CryptStringToBinaryW(
      raw_pem, 0, CRYPT_STRING_BASE64HEADER, der.data(), &der_size,
      nullptr, nullptr);
  CoTaskMemFree(raw_pem);
  if (!decoded) {
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  PCCERT_CONTEXT context = CertCreateCertificateContext(
      X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, der.data(), der_size);
  if (context == nullptr || CertVerifyTimeValidity(nullptr, context->pCertInfo) != 0) {
    if (context != nullptr) {
      CertFreeCertificateContext(context);
    }
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  CERT_CHAIN_PARA chain_parameters{};
  chain_parameters.cbSize = sizeof(chain_parameters);
  PCCERT_CHAIN_CONTEXT chain = nullptr;
  const bool built = CertGetCertificateChain(
      nullptr, context, nullptr, context->hCertStore, &chain_parameters,
      0, nullptr, &chain);
  const DWORD allowed_errors =
      CERT_TRUST_IS_UNTRUSTED_ROOT | CERT_TRUST_IS_PARTIAL_CHAIN;
  if (!built || chain == nullptr ||
      (chain->TrustStatus.dwErrorStatus & ~allowed_errors) != 0 ||
      (chain->TrustStatus.dwErrorStatus &
       (CERT_TRUST_IS_UNTRUSTED_ROOT | CERT_TRUST_IS_PARTIAL_CHAIN)) == 0) {
    if (chain != nullptr) {
      CertFreeCertificateChain(chain);
    }
    CertFreeCertificateContext(context);
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  const auto wide_host = Utf16(host);
  SSL_EXTRA_CERT_CHAIN_POLICY_PARA ssl{};
  ssl.cbSize = sizeof(ssl);
  ssl.dwAuthType = AUTHTYPE_SERVER;
  ssl.pwszServerName = const_cast<LPWSTR>(wide_host.c_str());
  CERT_CHAIN_POLICY_PARA policy{};
  policy.cbSize = sizeof(policy);
  policy.pvExtraPolicyPara = &ssl;
  CERT_CHAIN_POLICY_STATUS policy_status{};
  policy_status.cbSize = sizeof(policy_status);
  const bool policy_checked = CertVerifyCertificateChainPolicy(
      CERT_CHAIN_POLICY_SSL, chain, &policy, &policy_status);
  const bool trust_only_failure =
      policy_status.dwError == CERT_E_UNTRUSTEDROOT ||
      policy_status.dwError == CERT_E_CHAINING;
  std::array<BYTE, 32> digest{};
  DWORD digest_size = static_cast<DWORD>(digest.size());
  const bool hashed = CryptHashCertificate2(
      BCRYPT_SHA256_ALGORITHM, 0, nullptr, context->pbCertEncoded,
      context->cbCertEncoded, digest.data(), &digest_size);
  CertFreeCertificateChain(chain);
  CertFreeCertificateContext(context);
  if (!policy_checked || !trust_only_failure || !hashed ||
      digest_size != digest.size()) {
    CoTaskMemFree(raw_subject);
    CoTaskMemFree(raw_issuer);
    return std::nullopt;
  }
  CertificateDetails details{
      Hex(digest.data(), digest_size),
      Utf8(raw_subject),
      Utf8(raw_issuer),
      static_cast<int64_t>(valid_from * 1000),
      static_cast<int64_t>(valid_to * 1000),
  };
  CoTaskMemFree(raw_subject);
  CoTaskMemFree(raw_issuer);
  return details;
}

}  // namespace

std::string AleraBrowserPlugin::RegisterDecision(
    BrowserDecisionKind kind,
    const std::string& page_id,
    std::function<void(const EncodableMap&)> resolve,
    std::function<void()> deny) {
  const auto id = "decision-" + std::to_string(next_decision_id_++);
  auto [iterator, inserted] = decisions_.emplace(
      id,
      PendingBrowserDecision{
          kind, page_id, std::move(resolve), std::move(deny)});
  if (!inserted) {
    return {};
  }
  const UINT_PTR timer_id =
      SetTimer(
          nullptr, 0,
          kind == BrowserDecisionKind::tls
              ? kBrowserTlsDecisionTimeoutMilliseconds
              : kBrowserDecisionTimeoutMilliseconds,
          DecisionTimeout);
  if (timer_id == 0) {
    auto failed = std::move(iterator->second);
    decisions_.erase(iterator);
    failed.deny();
    return {};
  }
  iterator->second.timer_id = timer_id;
  g_decision_timers[timer_id] = {this, id};
  return id;
}

void CancelBrowserDecisionTimeout(PendingBrowserDecision* decision) {
  if (decision == nullptr || decision->timer_id == 0) {
    return;
  }
  KillTimer(nullptr, decision->timer_id);
  g_decision_timers.erase(decision->timer_id);
  decision->timer_id = 0;
}

void AleraBrowserPlugin::ResolveDecision(
    const EncodableMap& arguments,
    MethodResultPtr result) {
  const auto id = StringValue(arguments, "decisionId");
  if (!id.has_value()) {
    Error(
        std::move(result), "invalid_decision",
        "A browser decision id is required.");
    return;
  }
  const auto iterator = decisions_.find(*id);
  if (iterator == decisions_.end()) {
    Error(
        std::move(result), "stale_decision",
        "The browser decision is no longer pending.");
    return;
  }
  auto decision = std::move(iterator->second);
  decisions_.erase(iterator);
  CancelBrowserDecisionTimeout(&decision);
  decision.resolve(arguments);
  Success(std::move(result));
}

void AleraBrowserPlugin::ExpireDecision(
    const std::string& decision_id) {
  const auto iterator = decisions_.find(decision_id);
  if (iterator == decisions_.end()) {
    return;
  }
  auto decision = std::move(iterator->second);
  decisions_.erase(iterator);
  decision.timer_id = 0;
  decision.deny();
}

void AleraBrowserPlugin::StartPermissionDecision(
    const std::shared_ptr<BrowserPage>& page,
    ICoreWebView2PermissionRequestedEventArgs* arguments) {
  COREWEBVIEW2_PERMISSION_KIND kind =
      COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
  LPWSTR raw_origin = nullptr;
  arguments->get_PermissionKind(&kind);
  arguments->get_Uri(&raw_origin);
  const std::string permission = PermissionName(kind);
  const std::string origin = Utf8(raw_origin);
  CoTaskMemFree(raw_origin);
  if (!event_sink_ || permission == "unknown" ||
      !IsAllowedBrowserUrl(origin)) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }
  ComPtr<ICoreWebView2PermissionRequestedEventArgs3> arguments3;
  if (FAILED(arguments->QueryInterface(IID_PPV_ARGS(&arguments3))) ||
      FAILED(arguments3->put_SavesInProfile(FALSE))) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }

  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(arguments->GetDeferral(&deferral)) || !deferral) {
    arguments->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }
  ComPtr<ICoreWebView2PermissionRequestedEventArgs> held_arguments =
      arguments;
  auto complete =
      [held_arguments, deferral](bool allow) {
        held_arguments->put_State(
            allow ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
                  : COREWEBVIEW2_PERMISSION_STATE_DENY);
        deferral->Complete();
      };
  const auto decision_id = RegisterDecision(
      BrowserDecisionKind::permission, page->id(),
      [complete](const EncodableMap& value) {
        complete(StringValue(value, "decision").value_or("deny") == "allow");
      },
      [complete]() { complete(false); });
  if (decision_id.empty()) {
    return;
  }
  auto event = BrowserEvent("permissionRequest", page->id());
  event[EncodableValue("decisionId")] = EncodableValue(decision_id);
  event[EncodableValue("origin")] = EncodableValue(origin);
  event[EncodableValue("resources")] =
      EncodableValue(flutter::EncodableList{EncodableValue(permission)});
  Emit(std::move(event));
}

void AleraBrowserPlugin::StartTlsDecision(
    const std::shared_ptr<BrowserPage>& page,
    ICoreWebView2ServerCertificateErrorDetectedEventArgs* arguments) {
  arguments->put_Action(COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
  if (!event_sink_) {
    return;
  }
  COREWEBVIEW2_WEB_ERROR_STATUS error_status =
      COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
  LPWSTR raw_uri = nullptr;
  ComPtr<ICoreWebView2Certificate> certificate;
  if (FAILED(arguments->get_ErrorStatus(&error_status)) ||
      error_status != COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID ||
      FAILED(arguments->get_RequestUri(&raw_uri)) ||
      raw_uri == nullptr ||
      FAILED(arguments->get_ServerCertificate(&certificate)) ||
      !certificate) {
    CoTaskMemFree(raw_uri);
    return;
  }
  const std::string uri = Utf8(raw_uri);
  CoTaskMemFree(raw_uri);
  if (!IsLocalCertificateUrl(uri)) {
    return;
  }
  const std::string host = BrowserUrlHost(uri);
  const auto details = InspectCertificate(certificate.Get(), host);
  if (!details.has_value()) {
    return;
  }
  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(arguments->GetDeferral(&deferral)) || !deferral) {
    return;
  }
  ComPtr<ICoreWebView2ServerCertificateErrorDetectedEventArgs>
      held_arguments = arguments;
  const auto complete = [held_arguments, deferral](bool allow) {
    held_arguments->put_Action(
        allow ? COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_ALWAYS_ALLOW
              : COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
    deferral->Complete();
  };
  const auto decision_id = RegisterDecision(
      BrowserDecisionKind::tls, page->id(),
      [complete](const EncodableMap& value) {
        complete(StringValue(value, "decision").value_or("cancel") ==
                 "proceed");
      },
      [complete]() { complete(false); });
  if (decision_id.empty()) {
    return;
  }
  auto event = BrowserEvent("tlsRequest", page->id());
  event[EncodableValue("decisionId")] = EncodableValue(decision_id);
  event[EncodableValue("url")] = EncodableValue(uri);
  event[EncodableValue("host")] = EncodableValue(host);
  event[EncodableValue("fingerprintSha256")] =
      EncodableValue(details->fingerprint);
  event[EncodableValue("subject")] = EncodableValue(details->subject);
  event[EncodableValue("issuer")] = EncodableValue(details->issuer);
  event[EncodableValue("validFrom")] =
      EncodableValue(details->valid_from_millis);
  event[EncodableValue("validTo")] =
      EncodableValue(details->valid_to_millis);
  event[EncodableValue("errors")] =
      EncodableValue(flutter::EncodableList{
          EncodableValue("untrustedIssuer")});
  Emit(std::move(event));
}

}  // namespace alera_browser
