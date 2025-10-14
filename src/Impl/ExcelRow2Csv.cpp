#include "ExcelValue.h"
#include "Utils.h"
#include <string>
#include <vector>

std::string excelRow2Csv(std::vector<ExcelValue> line) {
  // Pre-calculate approximate size for string pre-allocation
  size_t estimated_size = 0;
  for (const auto &value : line) {
    std::visit(
        [&estimated_size](const auto &v) {
          using T = std::decay_t<decltype(v)>;
          if constexpr (std::is_same_v<T, std::string>) {
            estimated_size +=
                v.length() + 3; // +3 for potential quotes and comma
          } else if constexpr (std::is_same_v<T, double>) {
            estimated_size += 6; // should be enough
          } else if constexpr (std::is_same_v<T, bool>) {
            estimated_size += 6; // "false" + comma or "true" + comma
          }
        },
        value);
  }

  // Reserve space for the result string
  std::string result;
  result.reserve(estimated_size);

  // Convert each value to CSV format
  for (size_t i = 0; i < line.size(); ++i) {
    if (i > 0) {
      result += ',';
    }

    std::visit(
        [&result](const auto &v) {
          using T = std::decay_t<decltype(v)>;
          if constexpr (std::is_same_v<T, std::string>) {
            // Check if string needs quoting (contains comma, quote, or newline)
            bool needs_quoting = v.find(',') != std::string::npos ||
                                 v.find('"') != std::string::npos ||
                                 v.find('\n') != std::string::npos ||
                                 v.find('\r') != std::string::npos;

            if (needs_quoting) {
              result += '"';
              // Escape internal quotes by doubling them
              for (char c : v) {
                if (c == '"') {
                  result += "\"\"";
                } else {
                  result += c;
                }
              }
              result += '"';
            } else {
              result += v;
            }
          } else if constexpr (std::is_same_v<T, double>) {
            result += doubleToString(v);
          } else if constexpr (std::is_same_v<T, bool>) {
            result += v ? "true" : "false";
          }
        },
        line[i]);
  }

  return result;
}