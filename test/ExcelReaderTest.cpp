#include "ExcelReader.h"
#include "Utils.h"
#include "doctest/doctest.h"

TEST_CASE("ExcelReader") {
  ExcelReader excelReader;

  int rowCount = 0;

  for (const auto &row :
       excelReader.read("./test/fixtures/sample_sheet.xlsx")) {
    switch (rowCount) {
    case 0: {
      CHECK(std::holds_alternative<std::string>(row[0]));
      CHECK(std::get<std::string>(row[0]) == "employee_id");

      CHECK(std::holds_alternative<std::string>(row[1]));
      CHECK(std::get<std::string>(row[1]) == "first_name");

      CHECK(std::holds_alternative<std::string>(row[2]));
      CHECK(std::get<std::string>(row[2]) == "last_name");

      CHECK(std::holds_alternative<std::string>(row[3]));
      CHECK(std::get<std::string>(row[3]) == "email");

      CHECK(std::holds_alternative<std::string>(row[4]));
      CHECK(std::get<std::string>(row[4]) == "department");

      CHECK(std::holds_alternative<std::string>(row[5]));
      CHECK(std::get<std::string>(row[5]) == "position");

      CHECK(std::holds_alternative<std::string>(row[6]));
      CHECK(std::get<std::string>(row[6]) == "hire_date");

      CHECK(std::holds_alternative<std::string>(row[7]));
      CHECK(std::get<std::string>(row[7]) == "salary");

      CHECK(std::holds_alternative<std::string>(row[8]));
      CHECK(std::get<std::string>(row[8]) == "location");

      CHECK(std::holds_alternative<std::string>(row[9]));
      CHECK(std::get<std::string>(row[9]) == "performance_score");

      CHECK(std::holds_alternative<std::string>(row[10]));
      CHECK(std::get<std::string>(row[10]) == "projects_completed");

      CHECK(std::holds_alternative<std::string>(row[11]));
      CHECK(std::get<std::string>(row[11]) == "active");

      break;
    }
    case 1: {
      CHECK(std::holds_alternative<std::string>(row[0]));
      CHECK(std::get<std::string>(row[0]) == "EMP0001");

      CHECK(std::holds_alternative<std::string>(row[1]));
      CHECK(std::get<std::string>(row[1]) == "Christopher");

      CHECK(std::holds_alternative<std::string>(row[2]));
      CHECK(std::get<std::string>(row[2]) == "Sanchez");

      CHECK(std::holds_alternative<std::string>(row[3]));
      CHECK(std::get<std::string>(row[3]) == "christopher.sanchez@company.com");

      CHECK(std::holds_alternative<std::string>(row[4]));
      CHECK(std::get<std::string>(row[4]) == "Operations");

      CHECK(std::holds_alternative<std::string>(row[5]));
      CHECK(std::get<std::string>(row[5]) == "Junior Developer");

      CHECK(std::holds_alternative<std::string>(row[6]));
      CHECK(std::get<std::string>(row[6]) == "2019-07-28");

      CHECK(std::holds_alternative<double>(row[7]));
      CHECK(std::get<double>(row[7]) == 111653);

      CHECK(std::holds_alternative<std::string>(row[8]));
      CHECK(std::get<std::string>(row[8]) == "Chicago");

      CHECK(std::holds_alternative<double>(row[9]));
      CHECK(std::get<double>(row[9]) == doctest::Approx(4.599999999999999));

      CHECK(std::holds_alternative<double>(row[10]));
      CHECK(std::get<double>(row[10]) == 23);

      // TODO: fix this
      // FIXME: should render as boolean, is string...
      // CHECK(std::holds_alternative<bool>(row[11]));
      // CHECK(std::get<bool>(row[11]) == "True");

      break;
    }
    }

    rowCount++;
  }

  CHECK(rowCount == 1001);
}