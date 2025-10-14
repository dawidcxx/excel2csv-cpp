#include "ExcelReader.h"
#include "Utils.h"
#include "doctest/doctest.h"

TEST_CASE("ExcelReader") {
  ExcelReader excelReader;

  int rowCount = 0;

  for (const auto &row :
       excelReader.read("./test/fixtures/sample_sheet.xlsx")) {
    rowCount++;
  }

  CHECK(rowCount == 1001);
}