// [LISTN] Sources/CoreSignEngine/include/MachOModifier.h
// Language: C++20 | File: MachOModifier.h | Target: iOS arm64 Mach-O Binary Manipulation
#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <fstream>
#include <memory>

namespace KSign {

struct MachOSliceInfo {
    uint32_t cpuType;
    uint32_t cpuSubtype;
    uint64_t fileOffset;
    uint64_t fileSize;
    bool is64Bit;
};

class MachOModifier {
public:
    explicit MachOModifier(const std::string& filePath);
    ~MachOModifier();

    bool load();
    bool save();
    bool saveTo(const std::string& outputPath);

    // Dylib injection (LC_LOAD_DYLIB)
    bool injectDylib(const std::string& dylibPath, bool isWeak = false);

    // Code signature management
    bool getCodeSignatureOffsetAndSize(uint64_t sliceOffset, uint32_t& dataOff, uint32_t& dataSize);
    bool updateCodeSignature(uint64_t sliceOffset, const std::vector<uint8_t>& signatureBlob);

    // Slices inspection
    const std::vector<MachOSliceInfo>& getSlices() const { return m_slices; }
    const std::vector<uint8_t>& getRawData() const { return m_buffer; }
    std::vector<uint8_t>& getMutableData() { return m_buffer; }

private:
    std::string m_filePath;
    std::vector<uint8_t> m_buffer;
    std::vector<MachOSliceInfo> m_slices;

    bool parseSlices();
    bool injectDylibIntoSlice(const MachOSliceInfo& slice, const std::string& dylibPath, bool isWeak);
};

} // namespace KSign
