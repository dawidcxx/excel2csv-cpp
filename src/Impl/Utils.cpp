#include "Utils.h"

#include <format>
#include <minizip/unzip.h>
#include <span>
#include <string>
#include <vector>

#include "generator.h"

generator<std::span<std::byte>>
ZipUtils::readFileChunked(unzFile file, std::string_view zipEntry) {
  if (unzLocateFile(file, zipEntry.data(), 0) != UNZ_OK) {
    throw MalformedZipFileException(
        std::format("Failed to locate file '{}' in ZIP archive", zipEntry));
  }

  if (unzOpenCurrentFile(file) != UNZ_OK) {
    throw MalformedZipFileException(
        std::format("Failed to open file '{}' in ZIP archive", zipEntry));
  }

  std::vector<std::byte> buffer(8192);
  int bytesRead;

  while ((bytesRead = unzReadCurrentFile(file, buffer.data(), buffer.size())) >
         0) {
    co_yield std::span<std::byte>(buffer.data(), bytesRead);
  }

  if (bytesRead < 0) {
    throw MalformedZipFileException("Failed to read file from ZIP archive");
  }

  unzCloseCurrentFile(file);
}

int stringToNumber(const std::string &str) {
  int result = 0;
  const char *ptr = str.data();
  const char *end = ptr + str.size();

  // Fast path: skip non-digits at start
  while (ptr < end && (*ptr < '0' || *ptr > '9')) {
    ++ptr;
  }

  // Convert digits
  while (ptr < end && *ptr >= '0' && *ptr <= '9') {
    result = result * 10 + (*ptr - '0');
    ++ptr;
  }

  return result;
}

std::string doubleToString(const double d) {
  if (d == 0.0)
    return "0";
  if (d != d)
    return "nan";
  if (d == std::numeric_limits<double>::infinity())
    return "inf";
  if (d == -std::numeric_limits<double>::infinity())
    return "-inf";

  std::string result;
  result.reserve(32);

  if (d < 0) {
    result += '-';
  }

  double abs_d = std::abs(d);

  // Handle integer part
  uint64_t integer_part = static_cast<uint64_t>(abs_d);
  double fractional_part = abs_d - integer_part;

  // Convert integer part
  if (integer_part == 0) {
    result += '0';
  } else {
    std::string int_str;
    int_str.reserve(20);
    while (integer_part > 0) {
      int_str += '0' + (integer_part % 10);
      integer_part /= 10;
    }
    std::reverse(int_str.begin(), int_str.end());
    result += int_str;
  }

  // Handle fractional part if non-zero
  if (fractional_part > 1e-15) {
    result += '.';

    // Extract up to 15 decimal places
    for (int i = 0; i < 15 && fractional_part > 1e-15; ++i) {
      fractional_part *= 10;
      int digit = static_cast<int>(fractional_part);
      result += '0' + digit;
      fractional_part -= digit;
    }

    // Remove trailing zeros
    while (result.back() == '0') {
      result.pop_back();
    }
  }

  return result;
}