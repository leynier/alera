#ifndef ALERA_BROWSER_WINDOWS_BROWSER_JSON_H_
#define ALERA_BROWSER_WINDOWS_BROWSER_JSON_H_

#include <map>
#include <optional>
#include <string>
#include <vector>

namespace alera_browser {

struct BrowserJsonValue {
  enum class Kind {
    null_value,
    boolean,
    number,
    string,
    array,
    object,
  };

  Kind kind = Kind::null_value;
  bool boolean = false;
  double number = 0;
  std::string string;
  std::vector<BrowserJsonValue> array;
  std::map<std::string, BrowserJsonValue> object;

  const BrowserJsonValue* Find(const std::string& key) const;
  std::optional<std::string> String() const;
  std::optional<double> Number() const;
  std::optional<bool> Boolean() const;
};

bool ParseBrowserJson(
    const std::string& input,
    BrowserJsonValue* value);

}  // namespace alera_browser

#endif
