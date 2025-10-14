#include "ExcelReader.h"
#include "Utils.h"
#include "doctest/doctest.h"
#include <iostream>
#include <variant>

// Helper function to print ExcelValue
void printExcelValue(const ExcelValue &value) {
  std::visit([](const auto &v) { std::cout << v; }, value);
}

TEST_CASE("ExcelReader") {
  ExcelReader excelReader;

  int rowCount = 0;

  for (const auto &row :
       excelReader.read("./test/fixtures/sample_sheet.xlsx")) {
    rowCount++;

    // Only process first few rows to avoid overwhelming output
    if (rowCount <= 3) {
      // Print row as CSV
      for (size_t i = 0; i < row.size(); ++i) {
        if (i > 0) {
          std::cout << ",";
        }
        printExcelValue(row[i]);
      }
      std::cout << std::endl;
    }

    // Stop after reasonable number for testing
    if (rowCount >= 10) {
      break;
    }
  }
}