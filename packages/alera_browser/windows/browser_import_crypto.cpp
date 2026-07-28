#include "browser_import_internal.h"

#include "browser_json.h"
#include "browser_value.h"

#include <bcrypt.h>
#include <wincrypt.h>
#include <windows.h>

#include <algorithm>
#include <fstream>
#include <iterator>
#include <limits>
#include <memory>

namespace alera_browser {
namespace {

struct AlgorithmCloser {
  void operator()(void* handle) const {
    if (handle != nullptr) {
      BCryptCloseAlgorithmProvider(
          static_cast<BCRYPT_ALG_HANDLE>(handle), 0);
    }
  }
};

struct KeyCloser {
  void operator()(void* handle) const {
    if (handle != nullptr) {
      BCryptDestroyKey(static_cast<BCRYPT_KEY_HANDLE>(handle));
    }
  }
};

using AlgorithmHandle = std::unique_ptr<void, AlgorithmCloser>;
using KeyHandle = std::unique_ptr<void, KeyCloser>;

std::optional<std::vector<uint8_t>> DecodeBase64(
    const std::string& value) {
  DWORD size = 0;
  if (!CryptStringToBinaryA(
          value.c_str(), static_cast<DWORD>(value.size()),
          CRYPT_STRING_BASE64, nullptr, &size, nullptr, nullptr)) {
    return std::nullopt;
  }
  std::vector<uint8_t> result(size);
  if (!CryptStringToBinaryA(
          value.c_str(), static_cast<DWORD>(value.size()),
          CRYPT_STRING_BASE64, result.data(), &size, nullptr, nullptr)) {
    return std::nullopt;
  }
  result.resize(size);
  return result;
}

std::optional<std::vector<uint8_t>> DpapiDecrypt(
    const uint8_t* data,
    size_t size) {
  if (data == nullptr || size == 0 ||
      size > (std::numeric_limits<DWORD>::max)()) {
    return std::nullopt;
  }
  DATA_BLOB input{
      static_cast<DWORD>(size),
      const_cast<BYTE*>(reinterpret_cast<const BYTE*>(data))};
  DATA_BLOB output{};
  if (!CryptUnprotectData(
          &input, nullptr, nullptr, nullptr, nullptr,
          CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return std::nullopt;
  }
  std::vector<uint8_t> result(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return result;
}

std::optional<std::vector<uint8_t>> Sha256(
    const std::string& value) {
  BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(
          &raw_algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) {
    return std::nullopt;
  }
  AlgorithmHandle algorithm(raw_algorithm);
  (void)algorithm;
  std::vector<uint8_t> digest(32);
  if (BCryptHash(
          raw_algorithm, nullptr, 0,
          reinterpret_cast<PUCHAR>(
              const_cast<char*>(value.data())),
          static_cast<ULONG>(value.size()), digest.data(),
          static_cast<ULONG>(digest.size())) < 0) {
    return std::nullopt;
  }
  return digest;
}

std::optional<std::vector<uint8_t>> AesGcmDecrypt(
    const uint8_t* cipher,
    size_t cipher_size,
    const uint8_t* nonce,
    size_t nonce_size,
    const uint8_t* tag,
    size_t tag_size,
    const std::vector<uint8_t>& key) {
  if (cipher_size > (std::numeric_limits<ULONG>::max)() ||
      nonce_size > (std::numeric_limits<ULONG>::max)() ||
      tag_size > (std::numeric_limits<ULONG>::max)() ||
      key.empty() ||
      key.size() > (std::numeric_limits<ULONG>::max)()) {
    return std::nullopt;
  }
  BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(
          &raw_algorithm, BCRYPT_AES_ALGORITHM, nullptr, 0) < 0) {
    return std::nullopt;
  }
  AlgorithmHandle algorithm(raw_algorithm);
  (void)algorithm;
  const ULONG mode_size =
      static_cast<ULONG>(sizeof(BCRYPT_CHAIN_MODE_GCM));
  if (BCryptSetProperty(
          raw_algorithm, BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(
              const_cast<wchar_t*>(BCRYPT_CHAIN_MODE_GCM)),
          mode_size, 0) < 0) {
    return std::nullopt;
  }
  ULONG object_size = 0;
  ULONG received = 0;
  if (BCryptGetProperty(
          raw_algorithm, BCRYPT_OBJECT_LENGTH,
          reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size),
          &received, 0) < 0) {
    return std::nullopt;
  }
  std::vector<uint8_t> key_object(object_size);
  BCRYPT_KEY_HANDLE raw_key = nullptr;
  if (BCryptGenerateSymmetricKey(
          raw_algorithm, &raw_key, key_object.data(), object_size,
          const_cast<PUCHAR>(key.data()),
          static_cast<ULONG>(key.size()), 0) < 0) {
    return std::nullopt;
  }
  KeyHandle key_handle(raw_key);
  (void)key_handle;
  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authentication;
  BCRYPT_INIT_AUTH_MODE_INFO(authentication);
  authentication.pbNonce = const_cast<PUCHAR>(nonce);
  authentication.cbNonce = static_cast<ULONG>(nonce_size);
  authentication.pbTag = const_cast<PUCHAR>(tag);
  authentication.cbTag = static_cast<ULONG>(tag_size);
  std::vector<uint8_t> plain(cipher_size);
  ULONG plain_size = 0;
  if (BCryptDecrypt(
          raw_key, const_cast<PUCHAR>(cipher),
          static_cast<ULONG>(cipher_size), &authentication, nullptr, 0,
          plain.data(), static_cast<ULONG>(plain.size()), &plain_size,
          0) < 0) {
    SecureZeroMemory(key_object.data(), key_object.size());
    return std::nullopt;
  }
  SecureZeroMemory(key_object.data(), key_object.size());
  plain.resize(plain_size);
  return plain;
}

}  // namespace

std::optional<std::vector<uint8_t>> LoadChromiumEncryptionKey(
    const std::filesystem::path& local_state,
    std::string* detail_code) {
  std::ifstream stream(local_state, std::ios::binary);
  if (!stream) {
    *detail_code = "cookie_key_not_found";
    return std::nullopt;
  }
  stream.seekg(0, std::ios::end);
  const auto size = stream.tellg();
  if (size < 0 || size > 16 * 1024 * 1024) {
    *detail_code = "cookie_key_invalid";
    return std::nullopt;
  }
  stream.seekg(0);
  std::string json{
      std::istreambuf_iterator<char>(stream),
      std::istreambuf_iterator<char>()};
  BrowserJsonValue root;
  const auto* os_crypt =
      ParseBrowserJson(json, &root) ? root.Find("os_crypt") : nullptr;
  const auto* encrypted_key =
      os_crypt == nullptr ? nullptr : os_crypt->Find("encrypted_key");
  const auto encoded =
      encrypted_key == nullptr ? std::nullopt : encrypted_key->String();
  auto decoded =
      encoded.has_value() ? DecodeBase64(*encoded) : std::nullopt;
  constexpr char kDpapiPrefix[] = "DPAPI";
  if (!decoded.has_value() || decoded->size() <= 5 ||
      !std::equal(
          decoded->begin(), decoded->begin() + 5, kDpapiPrefix)) {
    *detail_code = "cookie_key_invalid";
    return std::nullopt;
  }
  auto key = DpapiDecrypt(decoded->data() + 5, decoded->size() - 5);
  SecureZeroMemory(decoded->data(), decoded->size());
  if (!key.has_value()) {
    *detail_code = GetLastError() == ERROR_CANCELLED
                       ? "cookie_key_access_denied"
                       : "cookie_key_decryption_failed";
  }
  return key;
}

std::optional<std::string> DecryptChromiumCookie(
    const std::vector<uint8_t>& encrypted,
    const std::vector<uint8_t>& key,
    bool has_domain_digest,
    const std::string& domain,
    std::string* detail_code) {
  if (encrypted.empty()) {
    return std::string();
  }
  if (encrypted.size() >= 3 &&
      std::equal(encrypted.begin(), encrypted.begin() + 3, "v20")) {
    *detail_code = "cookie_app_bound_encryption";
    return std::nullopt;
  }
  std::optional<std::vector<uint8_t>> decrypted;
  const bool modern =
      encrypted.size() >= 3 &&
      (std::equal(encrypted.begin(), encrypted.begin() + 3, "v10") ||
       std::equal(encrypted.begin(), encrypted.begin() + 3, "v11"));
  if (modern) {
    if (encrypted.size() < 3 + 12 + 16 || key.empty()) {
      *detail_code = key.empty() ? "cookie_key_unavailable"
                                 : "cookie_encryption_invalid";
      return std::nullopt;
    }
    decrypted = AesGcmDecrypt(
        encrypted.data() + 15, encrypted.size() - 31,
        encrypted.data() + 3, 12,
        encrypted.data() + encrypted.size() - 16, 16, key);
  } else {
    decrypted = DpapiDecrypt(encrypted.data(), encrypted.size());
  }
  if (!decrypted.has_value()) {
    *detail_code = "cookie_decryption_failed";
    return std::nullopt;
  }
  if (has_domain_digest) {
    const auto digest = Sha256(domain);
    if (!digest.has_value() || decrypted->size() < digest->size() ||
        !std::equal(
            digest->begin(), digest->end(), decrypted->begin())) {
      *detail_code = "cookie_domain_digest_mismatch";
      return std::nullopt;
    }
    decrypted->erase(
        decrypted->begin(), decrypted->begin() + digest->size());
  }
  std::string value(decrypted->begin(), decrypted->end());
  SecureZeroMemory(decrypted->data(), decrypted->size());
  if (!value.empty() && Utf16(value).empty()) {
    *detail_code = "cookie_value_invalid_utf8";
    return std::nullopt;
  }
  return value;
}

}  // namespace alera_browser
