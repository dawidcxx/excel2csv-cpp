#include <iostream>
#include <string>

#include "ExcelReader.h"
#include "ExcelRow2Csv.h"
#include "Utils.h"
#include "argsparse.h"

int main(int argc, char *argv[]) {
  std::ios::sync_with_stdio(false);

  argparse::ArgumentParser program("excel2csv");

  program.add_argument("xlsxpath").help("Path to the Excel file to convert");

  try {
    program.parse_args(argc, argv);
  } catch (const std::runtime_error &err) {
    std::cerr << err.what() << std::endl;
    std::cerr << program;
    return 1;
  }

  std::string xlsxPath = program.get<std::string>("xlsxpath");

  ExcelReader excelReader;

  for (const auto &row : excelReader.read(xlsxPath)) {
    if (row.empty())
      continue;
    std::cout << excelRow2Csv(row) << std::endl;
  }

  return 0;
}
