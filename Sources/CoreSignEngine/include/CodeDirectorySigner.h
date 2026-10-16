// [LISTN] Sources/CoreSignEngine/include/CodeDirectorySigner.h
// Language: C++20 | File: CodeDirectorySigner.h | Target: iOS CodeDirectory & CMS SuperBlob Generation
#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace KSign {

struct SigningContext {
    std::string bundleIdentifier;
    std::string teamIdentifier;
    std::string infoPlistData;
    std::string codeResourcesData;
    std::string entitlementsXml;
    std::vector<uint8_t> entitlementsDer;
    std::vector<uint8_t> p12Data;
    std::string p12Password;
};

class CodeDirectorySigner {
public:
    CodeDirectorySigner();
    ~CodeDirectorySigner();

    // Signs Mach-O binary slice data and outputs full CS_SuperBlob
    bool generateSuperBlob(const uint8_t* machOData,
                           uint64_t codeLimit,
                           const SigningContext& context,
                           std::vector<uint8_t>& outputSuperBlob,
                           std::string& errorString);

private:
    std::vector<uint8_t> buildCodeDirectory(const uint8_t* machOData,
                                           uint64_t codeLimit,
                                           const SigningContext& context);

    std::vector<uint8_t> buildRequirementsBlob(const std::string& bundleIdentifier);
    std::vector<uint8_t> buildEntitlementsBlob(const std::string& entitlementsXml);
    std::vector<uint8_t> buildDerEntitlementsBlob(const std::vector<uint8_t>& derData);

    bool signBlobCMS(const std::vector<uint8_t>& cdBlob,
                     const std::vector<uint8_t>& p12Data,
                     const std::string& p12Password,
                     std::vector<uint8_t>& cmsBlobWrapper,
                     std::string& errorString);
};

} // namespace KSign
