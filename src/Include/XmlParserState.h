#include <string>
#include <variant>

struct WaitingForSheetData {};
struct WaitingForRow {};
struct WaitingForCell {};
struct WaitingForValue {
  std::string cellType;
};
struct InValue {
  std::string cellType;
  std::string cellValue;
};
struct Done {};

using XmlParserState =
    std::variant<WaitingForSheetData, WaitingForRow, WaitingForCell,
                 WaitingForValue, InValue, Done>;
