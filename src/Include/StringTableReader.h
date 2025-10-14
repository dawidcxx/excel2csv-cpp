#pragma once

#include <cstddef>
#include <expat.h>
#include <minizip/unzip.h>
#include <optional>
#include <string>
#include <vector>

class StringTableReader {
private:
  std::vector<std::string> string_table;
  std::string current_string;
  bool in_string_item = false;
  bool in_text_element = false;

  static void XMLCALL startElement(void *userData, const char *name,
                                   const char **atts);
  static void XMLCALL endElement(void *userData, const char *name);
  static void XMLCALL charDataHandler(void *userData, const char *s, int len);

public:
  void collect(unzFile excelFileRef);
  std::optional<std::string> getStringEntry(std::size_t stringIndex);
};
