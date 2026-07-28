#include "browser_import_internal.h"

#include <libsecret/secret.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <sqlite3.h>

#include <cstring>
#include <vector>

namespace {

constexpr gint64 kChromeToUnixEpochMicroseconds = 11644473600000000LL;

const SecretSchema kSecretSchemaV2 = {
    "chrome_libsecret_os_crypt_password_v2",
    SECRET_SCHEMA_DONT_MATCH_NAME,
    {{"application", SECRET_SCHEMA_ATTRIBUTE_STRING},
     {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING}}};
const SecretSchema kSecretSchemaV1 = {
    "chrome_libsecret_os_crypt_password",
    SECRET_SCHEMA_NONE,
    {{nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING}}};

void set_detail(BrowserCookieImportBatch* batch, const gchar* detail) {
  if (batch->detail_code == nullptr) {
    batch->detail_code = g_strdup(detail);
  }
}

const gchar* const* application_names(const gchar* source) {
  static const gchar* chrome[] = {
      "chrome", "google-chrome", "Chrome", nullptr};
  static const gchar* edge[] = {
      "microsoft-edge", "Microsoft Edge", "edge", nullptr};
  static const gchar* brave[] = {"brave", "Brave", nullptr};
  if (g_strcmp0(source, "edge") == 0) {
    return edge;
  }
  if (g_strcmp0(source, "brave") == 0) {
    return brave;
  }
  return chrome;
}

gchar* read_secret_service_password(const gchar* source) {
  const gchar* const* applications = application_names(source);
  for (guint index = 0; applications[index] != nullptr; index++) {
    GError* error = nullptr;
    gchar* password = secret_password_lookup_sync(
        &kSecretSchemaV2, nullptr, &error, "application",
        applications[index], nullptr);
    g_clear_error(&error);
    if (password != nullptr && *password != '\0') {
      return password;
    }
    secret_password_free(password);
  }
  GError* error = nullptr;
  gchar* password = secret_password_lookup_sync(
      &kSecretSchemaV1, nullptr, &error, nullptr);
  g_clear_error(&error);
  return password;
}

gboolean derive_key(const gchar* password, guchar key[16]) {
  static const guchar salt[] = "saltysalt";
  return PKCS5_PBKDF2_HMAC_SHA1(
             password, strlen(password), salt, sizeof(salt) - 1, 1,
             16, key) == 1;
}

gboolean decrypt_value(const guchar* encrypted,
                       gsize encrypted_length,
                       const gchar* password,
                       std::vector<guchar>* output) {
  if (encrypted_length <= 3 || password == nullptr) {
    return FALSE;
  }
  guchar key[16] = {};
  if (!derive_key(password, key)) {
    return FALSE;
  }
  static const guchar initialization_vector[16] = {
      ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
      ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
  EVP_CIPHER_CTX* context = EVP_CIPHER_CTX_new();
  if (context == nullptr) {
    OPENSSL_cleanse(key, sizeof(key));
    return FALSE;
  }
  output->resize(encrypted_length - 3 + EVP_MAX_BLOCK_LENGTH);
  int first_length = 0;
  int final_length = 0;
  const gboolean success =
      EVP_DecryptInit_ex(context, EVP_aes_128_cbc(), nullptr, key,
                         initialization_vector) == 1 &&
      EVP_DecryptUpdate(context, output->data(), &first_length, encrypted + 3,
                        encrypted_length - 3) == 1 &&
      EVP_DecryptFinal_ex(context, output->data() + first_length,
                          &final_length) == 1;
  EVP_CIPHER_CTX_free(context);
  OPENSSL_cleanse(key, sizeof(key));
  if (!success) {
    OPENSSL_cleanse(output->data(), output->size());
    output->clear();
    return FALSE;
  }
  output->resize(first_length + final_length);
  return TRUE;
}

gboolean verify_and_strip_domain_hash(const gchar* domain,
                                      gint database_version,
                                      std::vector<guchar>* value) {
  if (database_version < 24) {
    return TRUE;
  }
  if (value->size() < 32) {
    return FALSE;
  }
  guchar expected[32] = {};
  unsigned int digest_length = 0;
  if (EVP_Digest(domain, strlen(domain), expected, &digest_length,
                 EVP_sha256(), nullptr) != 1 ||
      digest_length != sizeof(expected) ||
      CRYPTO_memcmp(expected, value->data(), sizeof(expected)) != 0) {
    return FALSE;
  }
  value->erase(value->begin(), value->begin() + sizeof(expected));
  return TRUE;
}

gint database_version(sqlite3* database) {
  sqlite3_stmt* statement = nullptr;
  gint version = 0;
  if (sqlite3_prepare_v2(database,
                         "SELECT value FROM meta WHERE key='version'", -1,
                         &statement, nullptr) == SQLITE_OK &&
      sqlite3_step(statement) == SQLITE_ROW) {
    version = sqlite3_column_int(statement, 0);
  }
  sqlite3_finalize(statement);
  return version;
}

gboolean table_has_column(sqlite3* database, const gchar* column) {
  sqlite3_stmt* statement = nullptr;
  gboolean found = FALSE;
  if (sqlite3_prepare_v2(database, "PRAGMA table_info(cookies)", -1,
                         &statement, nullptr) != SQLITE_OK) {
    return FALSE;
  }
  while (sqlite3_step(statement) == SQLITE_ROW) {
    const gchar* name = reinterpret_cast<const gchar*>(
        sqlite3_column_text(statement, 1));
    if (g_strcmp0(name, column) == 0) {
      found = TRUE;
      break;
    }
  }
  sqlite3_finalize(statement);
  return found;
}

SoupCookie* cookie_from_row(sqlite3_stmt* statement,
                            gint version,
                            const gchar* v11_password,
                            BrowserCookieImportBatch* batch) {
  const gchar* domain = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 0));
  const gchar* name = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 1));
  const gchar* plaintext = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 2));
  const guchar* encrypted = static_cast<const guchar*>(
      sqlite3_column_blob(statement, 3));
  const gint encrypted_length = sqlite3_column_bytes(statement, 3);
  const gchar* path = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 4));
  const gchar* partition = reinterpret_cast<const gchar*>(
      sqlite3_column_text(statement, 10));
  if (domain == nullptr || *domain == '\0' || name == nullptr ||
      *name == '\0' || path == nullptr || *path != '/' ||
      (partition != nullptr && *partition != '\0')) {
    return nullptr;
  }
  const gboolean has_plaintext = plaintext != nullptr && *plaintext != '\0';
  if (has_plaintext && encrypted_length > 0) {
    set_detail(batch, "ambiguous_encrypted_cookie");
    return nullptr;
  }
  g_autofree gchar* decrypted_text = nullptr;
  const gchar* value = plaintext != nullptr ? plaintext : "";
  std::vector<guchar> decrypted;
  if (!has_plaintext && encrypted_length > 0) {
    const gboolean v10 =
        encrypted_length > 3 && memcmp(encrypted, "v10", 3) == 0;
    const gboolean v11 =
        encrypted_length > 3 && memcmp(encrypted, "v11", 3) == 0;
    const gchar* password = v10 ? "peanuts" : v11 ? v11_password : nullptr;
    if (password == nullptr ||
        !decrypt_value(encrypted, encrypted_length, password, &decrypted) ||
        !verify_and_strip_domain_hash(domain, version, &decrypted) ||
        memchr(decrypted.data(), '\0', decrypted.size()) != nullptr ||
        !g_utf8_validate(reinterpret_cast<const gchar*>(decrypted.data()),
                         decrypted.size(), nullptr)) {
      if (!decrypted.empty()) {
        OPENSSL_cleanse(decrypted.data(), decrypted.size());
      }
      set_detail(batch, v11 && v11_password == nullptr
                            ? "secret_service_key_unavailable"
                            : "encrypted_cookie_skipped");
      return nullptr;
    }
    decrypted_text = g_strndup(
        reinterpret_cast<const gchar*>(decrypted.data()), decrypted.size());
    OPENSSL_cleanse(decrypted.data(), decrypted.size());
    value = decrypted_text;
  }
  SoupCookie* cookie = soup_cookie_new(name, value, domain, path, -1);
  if (cookie == nullptr) {
    return nullptr;
  }
  soup_cookie_set_secure(cookie, sqlite3_column_int(statement, 6) != 0);
  soup_cookie_set_http_only(cookie, sqlite3_column_int(statement, 7) != 0);
  const gint same_site = sqlite3_column_int(statement, 9);
  soup_cookie_set_same_site_policy(
      cookie, same_site == 2 ? SOUP_SAME_SITE_POLICY_LAX
                             : same_site == 3
                                   ? SOUP_SAME_SITE_POLICY_STRICT
                                   : SOUP_SAME_SITE_POLICY_NONE);
  if (sqlite3_column_int(statement, 8) != 0) {
    const gint64 chrome_microseconds = sqlite3_column_int64(statement, 5);
    const gint64 unix_seconds =
        (chrome_microseconds - kChromeToUnixEpochMicroseconds) / 1000000;
    g_autoptr(GDateTime) expires =
        g_date_time_new_from_unix_utc(unix_seconds);
    if (expires != nullptr) {
      soup_cookie_set_expires(cookie, expires);
    }
  }
  return cookie;
}

}  // namespace

BrowserCookieImportBatch* browser_cookie_import_read_chromium(
    const gchar* source,
    const gchar* database_path) {
  BrowserCookieImportBatch* batch = browser_cookie_import_batch_new();
  sqlite3* database = nullptr;
  if (sqlite3_open_v2(database_path, &database,
                      SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                      nullptr) != SQLITE_OK) {
    sqlite3_close(database);
    batch->detail_code = g_strdup("source_read_failed");
    return batch;
  }
  sqlite3_busy_timeout(database, 500);
  sqlite3_exec(database, "PRAGMA query_only=ON", nullptr, nullptr, nullptr);
  const gint version = database_version(database);
  const gboolean has_same_site = table_has_column(database, "samesite");
  const gboolean has_partition =
      table_has_column(database, "top_frame_site_key");
  g_autofree gchar* query = g_strdup_printf(
      "SELECT host_key,name,value,encrypted_value,path,expires_utc,"
      "is_secure,is_httponly,is_persistent,%s,%s FROM cookies",
      has_same_site ? "samesite" : "0",
      has_partition ? "top_frame_site_key" : "''");
  sqlite3_stmt* statement = nullptr;
  if (sqlite3_prepare_v2(database, query, -1, &statement, nullptr) !=
      SQLITE_OK) {
    sqlite3_close(database);
    batch->detail_code = g_strdup("source_schema_unsupported");
    return batch;
  }
  gchar* v11_password = read_secret_service_password(source);
  while (batch->imported_count + batch->skipped_count < 100000) {
    const gint step = sqlite3_step(statement);
    if (step == SQLITE_DONE) {
      break;
    }
    if (step != SQLITE_ROW) {
      set_detail(batch, "source_read_failed");
      break;
    }
    SoupCookie* cookie =
        cookie_from_row(statement, version, v11_password, batch);
    if (cookie == nullptr) {
      batch->skipped_count++;
    } else {
      batch->cookies = g_list_prepend(batch->cookies, cookie);
      batch->imported_count++;
    }
  }
  if (batch->imported_count + batch->skipped_count == 100000) {
    set_detail(batch, "source_cookie_limit");
  }
  if (v11_password != nullptr) {
    secret_password_free(v11_password);
  }
  sqlite3_finalize(statement);
  sqlite3_close(database);
  batch->cookies = g_list_reverse(batch->cookies);
  return batch;
}
