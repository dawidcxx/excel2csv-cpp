#pragma once

#include <string>
#include <variant>

using ExcelValue = std::variant<std::string, double, bool>;
