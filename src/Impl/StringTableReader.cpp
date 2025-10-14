#include "StringTableReader.h"
#include "Utils.h"

#include <cstring>
#include <expat.h>
#include <stdexcept>

void XMLCALL StringTableReader::startElement(void *userData, const char *name,
                                             const char **atts) {
  auto *reader = static_cast<StringTableReader *>(userData);
  if (strcmp(name, "si") == 0) {
    reader->current_string.clear();
    reader->in_string_item = true;
  } else if (strcmp(name, "t") == 0 && reader->in_string_item) {
    reader->in_text_element = true;
  }
}

void XMLCALL StringTableReader::endElement(void *userData, const char *name) {
  auto *reader = static_cast<StringTableReader *>(userData);
  if (strcmp(name, "si") == 0) {
    // End of string item - add to string table
    reader->string_table.push_back(reader->current_string);
    reader->in_string_item = false;
  } else if (strcmp(name, "t") == 0) {
    // End of text element
    reader->in_text_element = false;
  }
}

void XMLCALL StringTableReader::charDataHandler(void *userData, const char *s,
                                                int len) {
  auto *reader = static_cast<StringTableReader *>(userData);
  if (reader->in_string_item && reader->in_text_element) {
    reader->current_string.append(s, len);
  }
}

void StringTableReader::collect(unzFile excelFileRef) {
  auto parser = XML_ParserCreate(nullptr);
  if (!parser) {
    throw new std::runtime_error("Failed to allocate parser");
  }

  XML_SetUserData(parser, this);
  XML_SetElementHandler(parser, StringTableReader::startElement,
                        StringTableReader::endElement);
  XML_SetCharacterDataHandler(parser, StringTableReader::charDataHandler);

  for (auto &chunk :
       ZipUtils::readFileChunked(excelFileRef, "xl/sharedStrings.xml")) {
    auto start = reinterpret_cast<char *>(chunk.data());
    int end = chunk.size();
    if (XML_Parse(parser, start, end, XML_FALSE) == XML_FALSE) {
      XML_ParserFree(parser);
      throw MalformedExcelFileException(
          "Error while reading xl/sharedStrings.xml");
    }
  }
  XML_ParserFree(parser);
}

std::optional<std::string>
StringTableReader::getStringEntry(std::size_t stringIndex) {
  if (stringIndex >= string_table.size()) {
    return std::nullopt;
  }
  return string_table[stringIndex];
}