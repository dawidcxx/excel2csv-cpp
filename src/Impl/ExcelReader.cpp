#include "ExcelReader.h"

#include <cassert>
#include <cstring>
#include <format>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

#include "StringTableReader.h"
#include "Utils.h"
#include "XmlParserState.h"
#include "expat.h"

ExcelValue createExcelValue(StringTableReader &stringTableReader,
                            InValue xmlParserState);

class ExcelRowBuilder {
private:
  std::vector<ExcelValue> values;
  bool is_done = false;

public:
  void push(ExcelValue value) {
    assert(!this->isBuilt());
    this->values.push_back(value);
  }
  void seal() { this->is_done = true; }
  bool isBuilt() const { return this->is_done == true; }
  std::vector<ExcelValue> reset() {
    std::vector<ExcelValue> result = std::move(this->values);
    this->values.clear();
    this->is_done = false;
    return result;
  }
};

class XmlParser {
private:
  XmlParserState m_state;

  StringTableReader &stringTableReader;
  std::vector<std::vector<ExcelValue>> m_rows;
  ExcelRowBuilder m_currentRowBuilder;

public:
  XmlParser(StringTableReader &stringTableParser)
      : stringTableReader(stringTableParser), m_state(WaitingForSheetData{}) {}

  void onElementStart(const char *name, const char **atts) {
    std::visit(
        [this, name, atts](auto &&state) {
          using StateType = std::decay_t<decltype(state)>;

          if constexpr (std::is_same_v<StateType, WaitingForSheetData>) {
            if (strcmp(name, "sheetData") == 0) {
              m_state = WaitingForRow{};
            }
          } else if constexpr (std::is_same_v<StateType, WaitingForRow>) {
            if (strcmp(name, "row") == 0) {
              m_state = WaitingForCell{};
            }
          } else if constexpr (std::is_same_v<StateType, WaitingForCell>) {
            if (strcmp(name, "c") == 0) {
              std::string cellType;
              for (int i = 0; atts[i]; i += 2) {
                if (strcmp(atts[i], "t") == 0) {
                  cellType = atts[i + 1];
                  break;
                }
              }
              m_state = WaitingForValue{std::move(cellType)};
            }
          } else if constexpr (std::is_same_v<StateType, WaitingForValue>) {
            if (strcmp(name, "v") == 0) {
              m_state = InValue{state.cellType, ""};
            }
          }
        },
        m_state);
  }

  void onElementEnd(const char *name) {
    std::visit(
        [this, name](auto &&state) {
          using StateType = std::decay_t<decltype(state)>;

          if constexpr (std::is_same_v<StateType, InValue>) {
            if (strcmp(name, "v") == 0) {
              auto excelValue = createExcelValue(stringTableReader, state);
              m_currentRowBuilder.push(excelValue);
              m_state = WaitingForCell{};
            }
          } else if constexpr (std::is_same_v<StateType, WaitingForCell>) {
            if (strcmp(name, "row") == 0) {
              // Row is complete
              m_currentRowBuilder.seal();
              m_rows.push_back(m_currentRowBuilder.reset());
              m_state = WaitingForRow{};
            }
          } else if constexpr (std::is_same_v<StateType, WaitingForRow>) {
            if (strcmp(name, "sheetData") == 0) {
              m_state = Done{};
            }
          }
        },
        m_state);
  }

  void onCharacterData(const char *s, int len) {
    std::visit(
        [this, s, len](auto &&state) {
          using StateType = std::decay_t<decltype(state)>;

          if constexpr (std::is_same_v<StateType, InValue>) {
            std::get<InValue>(m_state).cellValue.append(s, len);
          }
        },
        m_state);
  }

  std::vector<std::vector<ExcelValue>> extractCompletedRows() {
    std::vector<std::vector<ExcelValue>> result = std::move(m_rows);
    m_rows.clear();
    return result;
  }
};

void XMLCALL startElement(void *userData, const char *name, const char **atts) {
  auto xmlParser = static_cast<XmlParser *>(userData);
  xmlParser->onElementStart(name, atts);
}

void XMLCALL endElement(void *userData, const char *name) {
  auto xmlParser = static_cast<XmlParser *>(userData);
  xmlParser->onElementEnd(name);
}

void XMLCALL charDataHandler(void *userData, const char *s, int len) {
  auto xmlParser = static_cast<XmlParser *>(userData);
  xmlParser->onCharacterData(s, len);
}

generator<std::vector<ExcelValue>>
ExcelReader::read(std::string_view filePath) {
  std::ifstream file(filePath.data(), std::ios::binary | std::ios::ate);
  if (!file.is_open()) {
    throw MalformedExcelFileException(
        std::format("Provided file '{}' is missing", filePath.data()));
  }

  auto excelZipArchive = ZipUtils::open(filePath);
  if (!excelZipArchive.has_value()) {
    throw MalformedExcelFileException(
        std::format("Failed to open Excel file '{}'", filePath.data()));
  }

  StringTableReader stringTableReader;
  stringTableReader.collect(excelZipArchive.value());

  auto parser = XML_ParserCreate(nullptr);
  if (!parser) {
    throw std::runtime_error("Failed to allocate parser");
  }

  XmlParser rowParser(stringTableReader);

  XML_SetUserData(parser, &rowParser);
  XML_SetElementHandler(parser, startElement, endElement);
  XML_SetCharacterDataHandler(parser, charDataHandler);
  XML_SetParamEntityParsing(parser, XML_PARAM_ENTITY_PARSING_NEVER);

  // Parse the XML file chunk by chunk and yield rows as they're completed
  for (auto &chunk : ZipUtils::readFileChunked(excelZipArchive.value(),
                                               "xl/worksheets/sheet1.xml")) {
    auto start = reinterpret_cast<char *>(chunk.data());
    int end = chunk.size();
    if (XML_Parse(parser, start, end, XML_FALSE) == XML_FALSE) {
      XML_ParserFree(parser);
      throw MalformedExcelFileException(
          "Error while reading xl/worksheets/sheet1.xml");
    }

    // After parsing each chunk, yield any completed rows
    auto completedRows = rowParser.extractCompletedRows();
    for (auto &row : completedRows) {
      co_yield std::move(row);
    }
  }

  // Parse the final chunk
  if (XML_Parse(parser, nullptr, 0, XML_TRUE) == XML_FALSE) {
    XML_ParserFree(parser);
    throw MalformedExcelFileException(
        "Error finalizing XML parse of xl/worksheets/sheet1.xml");
  }

  // Yield any remaining completed rows
  auto remainingRows = rowParser.extractCompletedRows();
  for (auto &row : remainingRows) {
    co_yield std::move(row);
  }

  XML_ParserFree(parser);
};

ExcelValue createExcelValue(StringTableReader &stringTableReader,
                            InValue state) {
  ExcelValue value;
  if (state.cellType == "s") {
    int index = stringToNumber(state.cellValue);
    auto stringEntry = stringTableReader.getStringEntry(index);
    value = stringEntry.has_value() ? stringEntry.value() : state.cellValue;
  } else if (state.cellType == "b") {
    // Boolean type
    value = (state.cellValue == "1");
  } else {
    // Numeric type (empty cellType means number)
    try {
      value = std::stod(state.cellValue);
    } catch (const std::exception &) {
      value = state.cellValue; // Fallback to string if conversion fails
    }
  }

  return value;
}