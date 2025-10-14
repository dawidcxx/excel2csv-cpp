#include <cstddef>
#include <minizip/unzip.h>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

#include "generator.h"

class MalformedZipFileException : public std::runtime_error {
public:
  explicit MalformedZipFileException(const std::string &msg)
      : std::runtime_error(msg) {}
};

class MalformedExcelFileException : public std::runtime_error {
public:
  explicit MalformedExcelFileException(const std::string &msg)
      : std::runtime_error(msg) {}
};

class ZipUtils {
public:
  static std::optional<unzFile> open(std::string_view filePath) {
    unzFile file = unzOpen(filePath.data());
    if (file == nullptr) {
      return std::nullopt;
    }
    return file;
  }

  static generator<std::span<std::byte>>
  readFileChunked(unzFile file, std::string_view zipEntry);
};

int stringToNumber(const std::string &str);
std::string doubleToString(const double d);