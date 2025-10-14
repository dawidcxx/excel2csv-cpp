#pragma once

#include "ExcelValue.h"
#include "generator.h"
#include <vector>

class ExcelReader {
public:
  generator<std::vector<ExcelValue>> read(std::string_view filePath);
};