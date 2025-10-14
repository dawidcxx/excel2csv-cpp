#include "StringTableReader.h"
#include "Utils.h"
#include "doctest/doctest.h"

TEST_CASE("StringTableReader") {
  auto file = ZipUtils::open("./test/fixtures/sample_sheet.xlsx").value();

  StringTableReader stringTableReader;
  stringTableReader.collect(file);

  auto entry = stringTableReader.getStringEntry(5);

  REQUIRE(entry.has_value());
  REQUIRE_MESSAGE(entry.has_value(),
                  "Should contain a string value at index 5");
  REQUIRE_MESSAGE(entry.value() == "position",
                  "Sheet string value at index 5 should match expected value");
}