#include "ExcelRow2Csv.h"
#include "ExcelValue.h"
#include "doctest/doctest.h"
#include <vector>

TEST_CASE("excelRow2Csv") {
  SUBCASE("Basic test case featuring multiple different values") {
    std::vector<ExcelValue> line = {ExcelValue("Hello World"), ExcelValue(3.14),
                                    ExcelValue(true), ExcelValue(""),
                                    ExcelValue("I heckin love \"csv\"")};
    auto csvLine = excelRow2Csv(line);
    CHECK(csvLine == "Hello World,3.14,true,,\"I heckin love \"\"csv\"\"\"");
  }
}