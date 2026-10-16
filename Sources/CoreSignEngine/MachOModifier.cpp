// [LISTN] Sources/CoreSignEngine/MachOModifier.cpp
// Language: C++20 | File: MachOModifier.cpp | Target: iOS arm64 Mach-O Binary Manipulation
#include "MachOModifier.h"
#include <cstring>
#include <iostream>
#include <algorithm>

#if defined(__APPLE__)
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <arpa/inet.h>
#else
// Standalone definitions for cross-compilation host verification
#define FAT_MAGIC 0xcafebabe
#define FAT_CIGAM 0xbebafeca
#define MH_MAGIC 0xfeedface
#define MH_CIGAM 0xcefaedfe
#define MH_MAGIC_64 0xfeedfacf
#define MH_CIGAM_64 0xcffaedfe
#define LC_SEGMENT_64 0x19
#define LC_LOAD_DYLIB 0xc
#define LC_LOAD_WEAK_DYLIB (0x18 | 0x80000000)
#define LC_CODE_SIGNATURE 0x1d

struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};

struct fat_arch {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};

struct mach_header_64 {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

union lc_str {
    uint32_t offset;
};

struct dylib {
    union lc_str name;
    uint32_t timestamp;
    uint32_t current_version;
    uint32_t compatibility_version;
};

struct dylib_command {
    uint32_t cmd;
    uint32_t cmdsize;
    struct dylib dylib;
};

struct segment_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    char segname[16];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t maxprot;
    uint32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

struct section_64 {
    char sectname[16];
    char segname[16];
    uint64_t addr;
    uint64_t size;
    uint32_t offset;
    uint32_t align;
    uint32_t reloff;
    uint32_t nreloc;
    uint32_t flags;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
};

struct linkedit_data_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t dataoff;
    uint32_t datasize;
};

static inline uint32_t swap_uint32(uint32_t val) {
    return ((val & 0xFF000000) >> 24) |
           ((val & 0x00FF0000) >> 8)  |
           ((val & 0x0000FF00) << 8)  |
           ((val & 0x000000FF) << 24);
}
#endif

namespace KSign {

MachOModifier::MachOModifier(const std::string& filePath)
    : m_filePath(filePath) {}

MachOModifier::~MachOModifier() = default;

bool MachOModifier::load() {
    std::ifstream file(m_filePath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        return false;
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    m_buffer.resize(static_cast<size_t>(size));
    if (!file.read(reinterpret_cast<char*>(m_buffer.data()), size)) {
        m_buffer.clear();
        return false;
    }
    return parseSlices();
}

bool MachOModifier::save() {
    return saveTo(m_filePath);
}

bool MachOModifier::saveTo(const std::string& outputPath) {
    std::ofstream file(outputPath, std::ios::binary | std::ios::trunc);
    if (!file.is_open()) {
        return false;
    }
    file.write(reinterpret_cast<const char*>(m_buffer.data()), m_buffer.size());
    return file.good();
}

bool MachOModifier::parseSlices() {
    m_slices.clear();
    if (m_buffer.size() < sizeof(uint32_t)) {
        return false;
    }

    uint32_t magic = *reinterpret_cast<const uint32_t*>(m_buffer.data());

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        bool swap = (magic == FAT_CIGAM);
        if (m_buffer.size() < sizeof(fat_header)) {
            return false;
        }
        const fat_header* fatHeader = reinterpret_cast<const fat_header*>(m_buffer.data());
        uint32_t nfat = swap ? swap_uint32(fatHeader->nfat_arch) : fatHeader->nfat_arch;

        size_t archTableSize = sizeof(fat_header) + (nfat * sizeof(fat_arch));
        if (m_buffer.size() < archTableSize) {
            return false;
        }

        const fat_arch* archs = reinterpret_cast<const fat_arch*>(m_buffer.data() + sizeof(fat_header));
        for (uint32_t i = 0; i < nfat; ++i) {
            uint32_t cputype = swap ? swap_uint32(archs[i].cputype) : archs[i].cputype;
            uint32_t cpusubtype = swap ? swap_uint32(archs[i].cpusubtype) : archs[i].cpusubtype;
            uint32_t offset = swap ? swap_uint32(archs[i].offset) : archs[i].offset;
            uint32_t size = swap ? swap_uint32(archs[i].size) : archs[i].size;

            MachOSliceInfo slice{};
            slice.cpuType = cputype;
            slice.cpuSubtype = cpusubtype;
            slice.fileOffset = offset;
            slice.fileSize = size;
            slice.is64Bit = (cputype & 0x01000000) != 0; // CPU_ARCH_ABI64
            m_slices.push_back(slice);
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        const mach_header_64* header = reinterpret_cast<const mach_header_64*>(m_buffer.data());
        MachOSliceInfo slice{};
        slice.cpuType = header->cputype;
        slice.cpuSubtype = header->cpusubtype;
        slice.fileOffset = 0;
        slice.fileSize = m_buffer.size();
        slice.is64Bit = true;
        m_slices.push_back(slice);
    } else {
        return false;
    }

    return !m_slices.empty();
}

bool MachOModifier::injectDylib(const std::string& dylibPath, bool isWeak) {
    if (m_slices.empty()) {
        return false;
    }

    bool allSuccess = true;
    for (const auto& slice : m_slices) {
        if (!slice.is64Bit) {
            continue;
        }
        if (!injectDylibIntoSlice(slice, dylibPath, isWeak)) {
            allSuccess = false;
        }
    }
    return allSuccess;
}

bool MachOModifier::injectDylibIntoSlice(const MachOSliceInfo& slice, const std::string& dylibPath, bool isWeak) {
    if (slice.fileOffset + sizeof(mach_header_64) > m_buffer.size()) {
        return false;
    }

    mach_header_64* header = reinterpret_cast<mach_header_64*>(m_buffer.data() + slice.fileOffset);
    uint32_t ncmds = header->ncmds;
    uint32_t sizeofcmds = header->sizeofcmds;

    size_t commandsOffset = slice.fileOffset + sizeof(mach_header_64);
    if (commandsOffset + sizeofcmds > m_buffer.size()) {
        return false;
    }

    // Check if dylib already injected
    size_t currOffset = commandsOffset;
    uint64_t firstSectionOffset = UINT64_MAX;

    for (uint32_t i = 0; i < ncmds; ++i) {
        if (currOffset + sizeof(load_command) > m_buffer.size()) break;
        const load_command* lc = reinterpret_cast<const load_command*>(m_buffer.data() + currOffset);

        if (lc->cmd == LC_LOAD_DYLIB || lc->cmd == LC_LOAD_WEAK_DYLIB) {
            const dylib_command* dylibCmd = reinterpret_cast<const dylib_command*>(lc);
            if (dylibCmd->dylib.name.offset < lc->cmdsize) {
                const char* nameStr = reinterpret_cast<const char*>(lc) + dylibCmd->dylib.name.offset;
                if (dylibPath == nameStr) {
                    // Already injected
                    return true;
                }
            }
        } else if (lc->cmd == LC_SEGMENT_64) {
            const segment_command_64* seg = reinterpret_cast<const segment_command_64*>(lc);
            if (seg->nsects > 0) {
                const section_64* sect = reinterpret_cast<const section_64*>(m_buffer.data() + currOffset + sizeof(segment_command_64));
                for (uint32_t s = 0; s < seg->nsects; ++s) {
                    if (sect[s].offset > 0 && sect[s].offset < firstSectionOffset) {
                        firstSectionOffset = sect[s].offset;
                    }
                }
            }
        }

        currOffset += lc->cmdsize;
    }

    // Calculate required space for dylib_command
    size_t pathLen = dylibPath.length() + 1;
    size_t cmdSize = sizeof(dylib_command) + pathLen;
    cmdSize = (cmdSize + 7) & ~7; // 8-byte aligned

    size_t endOfCmds = commandsOffset + sizeofcmds;

    // Verify header padding headroom
    if (firstSectionOffset != UINT64_MAX && (slice.fileOffset + firstSectionOffset) < (endOfCmds + cmdSize)) {
        // Insufficient padding between load commands and text sections
        return false;
    }

    // Zero-initialize destination and write dylib_command
    uint8_t* targetPtr = m_buffer.data() + endOfCmds;
    std::memset(targetPtr, 0, cmdSize);

    dylib_command* newCmd = reinterpret_cast<dylib_command*>(targetPtr);
    newCmd->cmd = isWeak ? LC_LOAD_WEAK_DYLIB : LC_LOAD_DYLIB;
    newCmd->cmdsize = static_cast<uint32_t>(cmdSize);
    newCmd->dylib.name.offset = sizeof(dylib_command);
    newCmd->dylib.timestamp = 2;
    newCmd->dylib.current_version = 0x00010000;
    newCmd->dylib.compatibility_version = 0x00010000;

    std::memcpy(targetPtr + sizeof(dylib_command), dylibPath.c_str(), dylibPath.length());

    // Update header
    header->ncmds += 1;
    header->sizeofcmds += static_cast<uint32_t>(cmdSize);

    return true;
}

bool MachOModifier::getCodeSignatureOffsetAndSize(uint64_t sliceOffset, uint32_t& dataOff, uint32_t& dataSize) {
    if (sliceOffset + sizeof(mach_header_64) > m_buffer.size()) return false;
    const mach_header_64* header = reinterpret_cast<const mach_header_64*>(m_buffer.data() + sliceOffset);

    size_t currOffset = sliceOffset + sizeof(mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (currOffset + sizeof(load_command) > m_buffer.size()) break;
        const load_command* lc = reinterpret_cast<const load_command*>(m_buffer.data() + currOffset);
        if (lc->cmd == LC_CODE_SIGNATURE) {
            const linkedit_data_command* csCmd = reinterpret_cast<const linkedit_data_command*>(lc);
            dataOff = csCmd->dataoff;
            dataSize = csCmd->datasize;
            return true;
        }
        currOffset += lc->cmdsize;
    }
    return false;
}

bool MachOModifier::updateCodeSignature(uint64_t sliceOffset, const std::vector<uint8_t>& signatureBlob) {
    if (sliceOffset + sizeof(mach_header_64) > m_buffer.size()) return false;
    mach_header_64* header = reinterpret_cast<mach_header_64*>(m_buffer.data() + sliceOffset);

    size_t currOffset = sliceOffset + sizeof(mach_header_64);
    linkedit_data_command* csCmd = nullptr;
    segment_command_64* linkeditSeg = nullptr;

    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (currOffset + sizeof(load_command) > m_buffer.size()) break;
        load_command* lc = reinterpret_cast<load_command*>(m_buffer.data() + currOffset);
        if (lc->cmd == LC_CODE_SIGNATURE) {
            csCmd = reinterpret_cast<linkedit_data_command*>(lc);
        } else if (lc->cmd == LC_SEGMENT_64) {
            segment_command_64* seg = reinterpret_cast<segment_command_64*>(lc);
            if (std::strncmp(seg->segname, "__LINKEDIT", 10) == 0) {
                linkeditSeg = seg;
            }
        }
        currOffset += lc->cmdsize;
    }

    if (!csCmd || !linkeditSeg) {
        return false;
    }

    uint32_t oldSigOffset = csCmd->dataoff;
    uint32_t oldSigSize = csCmd->datasize;

    // Truncate previous signature if placed at slice end
    uint64_t sliceEnd = sliceOffset + sliceOffset > 0 ? sliceOffset + oldSigOffset : oldSigOffset;
    if (oldSigOffset > 0 && oldSigOffset + oldSigSize == m_buffer.size()) {
        m_buffer.resize(oldSigOffset);
    }

    // 16-byte alignment padding for Mach-O signature blob
    size_t currentEnd = m_buffer.size();
    size_t alignedEnd = (currentEnd + 15) & ~15;
    if (alignedEnd > currentEnd) {
        m_buffer.resize(alignedEnd, 0);
    }

    uint32_t newSigOffset = static_cast<uint32_t>(m_buffer.size() - sliceOffset);
    uint32_t newSigSize = static_cast<uint32_t>(signatureBlob.size());

    // Append new SuperBlob signature
    m_buffer.insert(m_buffer.end(), signatureBlob.begin(), signatureBlob.end());

    // Update LC_CODE_SIGNATURE command
    csCmd->dataoff = newSigOffset;
    csCmd->datasize = newSigSize;

    // Update __LINKEDIT segment boundaries
    uint64_t linkeditEnd = newSigOffset + newSigSize;
    if (linkeditEnd > linkeditSeg->fileoff + linkeditSeg->filesize) {
        linkeditSeg->filesize = linkeditEnd - linkeditSeg->fileoff;
        // Align vmsize to page boundary (0x4000 = 16KB on iOS)
        linkeditSeg->vmsize = (linkeditSeg->filesize + 0x3FFF) & ~0x3FFF;
    }

    return true;
}

} // namespace KSign
