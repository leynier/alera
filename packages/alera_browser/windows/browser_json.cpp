#include "browser_json.h"

#include <charconv>
#include <cmath>
#include <cstdint>
#include <limits>

namespace alera_browser {
namespace {

void AppendUtf8(uint32_t code_point, std::string* value) {
  if (code_point <= 0x7f) {
    value->push_back(static_cast<char>(code_point));
  } else if (code_point <= 0x7ff) {
    value->push_back(static_cast<char>(0xc0 | (code_point >> 6)));
    value->push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
  } else if (code_point <= 0xffff) {
    value->push_back(static_cast<char>(0xe0 | (code_point >> 12)));
    value->push_back(
        static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
    value->push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
  } else {
    value->push_back(static_cast<char>(0xf0 | (code_point >> 18)));
    value->push_back(
        static_cast<char>(0x80 | ((code_point >> 12) & 0x3f)));
    value->push_back(
        static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
    value->push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
  }
}

class BrowserJsonParser {
 public:
  explicit BrowserJsonParser(const std::string& input) : input_(input) {}

  bool Parse(BrowserJsonValue* value) {
    SkipWhitespace();
    if (!ParseValue(0, value)) {
      return false;
    }
    SkipWhitespace();
    return offset_ == input_.size();
  }

 private:
  bool ParseValue(size_t depth, BrowserJsonValue* value) {
    if (depth > 64 || offset_ >= input_.size()) {
      return false;
    }
    const char current = input_[offset_];
    if (current == '"') {
      value->kind = BrowserJsonValue::Kind::string;
      return ParseString(&value->string);
    }
    if (current == '[') {
      return ParseArray(depth, value);
    }
    if (current == '{') {
      return ParseObject(depth, value);
    }
    if (current == 't' || current == 'f') {
      value->kind = BrowserJsonValue::Kind::boolean;
      return ParseLiteral(
          current == 't' ? "true" : "false", &value->boolean);
    }
    if (current == 'n') {
      value->kind = BrowserJsonValue::Kind::null_value;
      return Consume("null");
    }
    value->kind = BrowserJsonValue::Kind::number;
    return ParseNumber(&value->number);
  }

  bool ParseArray(size_t depth, BrowserJsonValue* value) {
    value->kind = BrowserJsonValue::Kind::array;
    ++offset_;
    SkipWhitespace();
    if (Take(']')) {
      return true;
    }
    while (value->array.size() < 100000) {
      BrowserJsonValue entry;
      if (!ParseValue(depth + 1, &entry)) {
        return false;
      }
      value->array.push_back(std::move(entry));
      SkipWhitespace();
      if (Take(']')) {
        return true;
      }
      if (!Take(',')) {
        return false;
      }
      SkipWhitespace();
    }
    return false;
  }

  bool ParseObject(size_t depth, BrowserJsonValue* value) {
    value->kind = BrowserJsonValue::Kind::object;
    ++offset_;
    SkipWhitespace();
    if (Take('}')) {
      return true;
    }
    while (value->object.size() < 100000) {
      std::string key;
      if (!ParseString(&key)) {
        return false;
      }
      SkipWhitespace();
      if (!Take(':')) {
        return false;
      }
      SkipWhitespace();
      BrowserJsonValue entry;
      if (!ParseValue(depth + 1, &entry) ||
          !value->object.emplace(std::move(key), std::move(entry)).second) {
        return false;
      }
      SkipWhitespace();
      if (Take('}')) {
        return true;
      }
      if (!Take(',')) {
        return false;
      }
      SkipWhitespace();
    }
    return false;
  }

  bool ParseString(std::string* value) {
    if (!Take('"')) {
      return false;
    }
    while (offset_ < input_.size()) {
      const unsigned char current = input_[offset_++];
      if (current == '"') {
        return true;
      }
      if (current < 0x20) {
        return false;
      }
      if (current != '\\') {
        value->push_back(static_cast<char>(current));
        continue;
      }
      if (offset_ >= input_.size()) {
        return false;
      }
      const char escaped = input_[offset_++];
      switch (escaped) {
        case '"':
        case '\\':
        case '/':
          value->push_back(escaped);
          break;
        case 'b':
          value->push_back('\b');
          break;
        case 'f':
          value->push_back('\f');
          break;
        case 'n':
          value->push_back('\n');
          break;
        case 'r':
          value->push_back('\r');
          break;
        case 't':
          value->push_back('\t');
          break;
        case 'u':
          if (!ParseUnicode(value)) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
    return false;
  }

  bool ParseUnicode(std::string* value) {
    uint32_t first = 0;
    if (!ParseHex(&first)) {
      return false;
    }
    if (first >= 0xdc00 && first <= 0xdfff) {
      return false;
    }
    if (first >= 0xd800 && first <= 0xdbff) {
      if (!Consume("\\u")) {
        return false;
      }
      uint32_t second = 0;
      if (!ParseHex(&second) || second < 0xdc00 || second > 0xdfff) {
        return false;
      }
      first = 0x10000 + ((first - 0xd800) << 10) +
              (second - 0xdc00);
    }
    AppendUtf8(first, value);
    return true;
  }

  bool ParseHex(uint32_t* value) {
    if (offset_ + 4 > input_.size()) {
      return false;
    }
    *value = 0;
    for (size_t index = 0; index < 4; ++index) {
      const char character = input_[offset_++];
      uint32_t digit = 0;
      if (character >= '0' && character <= '9') {
        digit = character - '0';
      } else if (character >= 'a' && character <= 'f') {
        digit = character - 'a' + 10;
      } else if (character >= 'A' && character <= 'F') {
        digit = character - 'A' + 10;
      } else {
        return false;
      }
      *value = (*value << 4) | digit;
    }
    return true;
  }

  bool ParseNumber(double* value) {
    const size_t start = offset_;
    if (Take('-') && offset_ == input_.size()) {
      return false;
    }
    if (Take('0')) {
      if (offset_ < input_.size() && input_[offset_] >= '0' &&
          input_[offset_] <= '9') {
        return false;
      }
    } else if (!Digits()) {
      return false;
    }
    if (Take('.') && !Digits()) {
      return false;
    }
    if (offset_ < input_.size() &&
        (input_[offset_] == 'e' || input_[offset_] == 'E')) {
      ++offset_;
      if (offset_ < input_.size() &&
          (input_[offset_] == '+' || input_[offset_] == '-')) {
        ++offset_;
      }
      if (!Digits()) {
        return false;
      }
    }
    const char* begin = input_.data() + start;
    const char* end = input_.data() + offset_;
    const auto parsed = std::from_chars(begin, end, *value);
    return parsed.ec == std::errc() && parsed.ptr == end &&
           std::isfinite(*value);
  }

  bool Digits() {
    const size_t start = offset_;
    while (offset_ < input_.size() && input_[offset_] >= '0' &&
           input_[offset_] <= '9') {
      ++offset_;
    }
    return offset_ != start;
  }

  bool ParseLiteral(const char* literal, bool* value) {
    *value = literal[0] == 't';
    return Consume(literal);
  }

  bool Consume(const char* literal) {
    size_t length = 0;
    while (literal[length] != '\0') {
      ++length;
    }
    if (input_.compare(offset_, length, literal) != 0) {
      return false;
    }
    offset_ += length;
    return true;
  }

  bool Take(char expected) {
    if (offset_ >= input_.size() || input_[offset_] != expected) {
      return false;
    }
    ++offset_;
    return true;
  }

  void SkipWhitespace() {
    while (offset_ < input_.size() &&
           (input_[offset_] == ' ' || input_[offset_] == '\n' ||
            input_[offset_] == '\r' || input_[offset_] == '\t')) {
      ++offset_;
    }
  }

  const std::string& input_;
  size_t offset_ = 0;
};

}  // namespace

const BrowserJsonValue* BrowserJsonValue::Find(
    const std::string& key) const {
  if (kind != Kind::object) {
    return nullptr;
  }
  const auto iterator = object.find(key);
  return iterator == object.end() ? nullptr : &iterator->second;
}

std::optional<std::string> BrowserJsonValue::String() const {
  return kind == Kind::string
             ? std::optional<std::string>(string)
             : std::nullopt;
}

std::optional<double> BrowserJsonValue::Number() const {
  return kind == Kind::number ? std::optional<double>(number)
                              : std::nullopt;
}

std::optional<bool> BrowserJsonValue::Boolean() const {
  return kind == Kind::boolean ? std::optional<bool>(boolean)
                               : std::nullopt;
}

bool ParseBrowserJson(
    const std::string& input,
    BrowserJsonValue* value) {
  return value != nullptr && BrowserJsonParser(input).Parse(value);
}

}  // namespace alera_browser
