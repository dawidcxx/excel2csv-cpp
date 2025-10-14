#include "Utils.h"
#include "doctest/doctest.h"
#include <chrono>
#include <vector>

TEST_CASE("ZipUtils") {
  auto file = ZipUtils::open("./test/fixtures/basic.zip").value();
  std::string output_string;
  for (const auto &chunk : ZipUtils::readFileChunked(file, "notes.txt")) {
    output_string.append(reinterpret_cast<const char *>(chunk.data()),
                         chunk.size());
  }
  CHECK(output_string == "123\n");
}

TEST_CASE("stringToNumber") {
  SUBCASE("extracts number from string with letters before") {
    CHECK(stringToNumber("dskjt31") == 31);
  }

  SUBCASE("extracts number from pure digit string") {
    CHECK(stringToNumber("51") == 51);
  }

  SUBCASE("extracts number from string with letters before and after") {
    CHECK(stringToNumber("hjdhdhfdhjdjkhjk51dlhfd") == 51);
  }

  SUBCASE("returns 0 for string with no digits") {
    CHECK(stringToNumber("gdlfggdgdgls") == 0);
  }

  SUBCASE("handles empty string") { CHECK(stringToNumber("") == 0); }

  SUBCASE("handles string with only digits") {
    CHECK(stringToNumber("123456") == 123456);
  }

  SUBCASE("handles single digit") { CHECK(stringToNumber("a7b") == 7); }
}

// run with: zig build run-test -Doptimize=ReleaseSmall --
// --test-case="BENCHMARK-stringToNumber"
TEST_CASE("BENCHMARK-stringToNumber") {
  std::vector<std::string> baseData = {"51",        "17",
                                       "123",       "456789",
                                       "dskjt31",   "hjdhdhfdhjdjkhjk51dlhfd",
                                       "abc123def", "xyz999",
                                       "42",        "test88test",
                                       "9876",      "prefix321suffix",
                                       "654",       "a1b2c3",
                                       "777",       "mixed444data",
                                       "100200",    "str555end",
                                       "2024",      "benchmark999test"};
  // testData is baseData looped over 1000 times
  std::vector<std::string> testData;
  for (int i = 0; i < 1000; ++i) {
    testData.insert(testData.end(), baseData.begin(), baseData.end());
  }

  SUBCASE("Run Benchmark") {
    auto start = std::chrono::high_resolution_clock::now();
    long sum = 0;
    for (const auto &str : testData) {
      sum += stringToNumber(str);
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto duration =
        std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    MESSAGE("stringToNumber test case ran in: ", duration.count(),
            "micro-seconds");
    CHECK(sum == 574165000);
  };
}