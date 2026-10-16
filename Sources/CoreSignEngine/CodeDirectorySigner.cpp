// [LISTN] Sources/CoreSignEngine/CodeDirectorySigner.cpp
// Language: C++20 | File: CodeDirectorySigner.cpp | Target: iOS CodeDirectory & CMS SuperBlob Generation
#include "CodeDirectorySigner.h"
#include <cstring>
#include <algorithm>
#include <vector>

#if defined(__APPLE__)
#include <arpa/inet.h>
#else
#define htonl(x) ((((x)&0xFF000000)>>24)|(((x)&0x00FF0000)>>8)|(((x)&0x0000FF00)<<8)|(((x)&0x000000FF)<<24))
#define ntohl(x) htonl(x)
#endif

#include <openssl/sha.h>
#include <openssl/pkcs12.h>
#include <openssl/cms.h>
#include <openssl/bio.h>
#include <openssl/err.h>

namespace KSign {

constexpr uint32_t CSMAGIC_CODEDIRECTORY      = 0xfade0c02;
constexpr uint32_t CSMAGIC_REQUIREMENTS        = 0xfade0c01;
constexpr uint32_t CSMAGIC_ENTITLEMENTS        = 0xfade7171;
constexpr uint32_t CSMAGIC_DER_ENTITLEMENTS    = 0xfade7172;
constexpr uint32_t CSMAGIC_BLOBWRAPPER         = 0xfade0b01;
constexpr uint32_t CSMAGIC_EMBEDDED_SIGNATURE  = 0xfade0cc0;

constexpr uint32_t CSSLOT_CODEDIRECTORY        = 0;
constexpr uint32_t CSSLOT_INFOPLIST            = 1;
constexpr uint32_t CSSLOT_REQUIREMENTS         = 2;
constexpr uint32_t CSSLOT_RESOURCEDIR          = 3;
constexpr uint32_t CSSLOT_APPLICATION          = 4;
constexpr uint32_t CSSLOT_ENTITLEMENTS         = 5;
constexpr uint32_t CSSLOT_DER_ENTITLEMENTS     = 7;
constexpr uint32_t CSSLOT_SIGNATURESLOT        = 0x10000;

#pragma pack(push, 1)
struct CS_BlobHeader {
    uint32_t magic;
    uint32_t length;
};

struct CS_BlobIndex {
    uint32_t type;
    uint32_t offset;
};

struct CS_CodeDirectoryHeader {
    uint32_t magic;
    uint32_t length;
    uint32_t version;
    uint32_t flags;
    uint32_t hashOffset;
    uint32_t identOffset;
    uint32_t nSpecialSlots;
    uint32_t nCodeSlots;
    uint32_t codeLimit;
    uint8_t  hashSize;
    uint8_t  hashType;
    uint8_t  platform;
    uint8_t  pageSize;
    uint32_t spare2;
    uint32_t scatterOffset;
    uint32_t teamIDOffset;
    uint32_t spare3;
    uint64_t codeLimit64;
    uint64_t execSegBase;
    uint64_t execSegLimit;
    uint64_t execSegFlags;
};
#pragma pack(pop)

static void sha256_buffer(const void* data, size_t len, uint8_t* outHash) {
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data, len);
    SHA256_Final(outHash, &ctx);
}

CodeDirectorySigner::CodeDirectorySigner() = default;
CodeDirectorySigner::~CodeDirectorySigner() = default;

std::vector<uint8_t> CodeDirectorySigner::buildRequirementsBlob(const std::string& bundleIdentifier) {
    // Standard minimal requirements blob
    std::vector<uint8_t> blob;
    blob.resize(sizeof(CS_BlobHeader) + 4);
    CS_BlobHeader* hdr = reinterpret_cast<CS_BlobHeader*>(blob.data());
    hdr->magic = htonl(CSMAGIC_REQUIREMENTS);
    hdr->length = htonl(static_cast<uint32_t>(blob.size()));
    // Count = 0 requirements expressions
    *reinterpret_cast<uint32_t*>(blob.data() + sizeof(CS_BlobHeader)) = 0;
    return blob;
}

std::vector<uint8_t> CodeDirectorySigner::buildEntitlementsBlob(const std::string& entitlementsXml) {
    std::vector<uint8_t> blob;
    size_t totalLen = sizeof(CS_BlobHeader) + entitlementsXml.length();
    blob.resize(totalLen);

    CS_BlobHeader* hdr = reinterpret_cast<CS_BlobHeader*>(blob.data());
    hdr->magic = htonl(CSMAGIC_ENTITLEMENTS);
    hdr->length = htonl(static_cast<uint32_t>(totalLen));
    std::memcpy(blob.data() + sizeof(CS_BlobHeader), entitlementsXml.data(), entitlementsXml.length());
    return blob;
}

std::vector<uint8_t> CodeDirectorySigner::buildDerEntitlementsBlob(const std::vector<uint8_t>& derData) {
    std::vector<uint8_t> blob;
    size_t totalLen = sizeof(CS_BlobHeader) + derData.size();
    blob.resize(totalLen);

    CS_BlobHeader* hdr = reinterpret_cast<CS_BlobHeader*>(blob.data());
    hdr->magic = htonl(CSMAGIC_DER_ENTITLEMENTS);
    hdr->length = htonl(static_cast<uint32_t>(totalLen));
    std::memcpy(blob.data() + sizeof(CS_BlobHeader), derData.data(), derData.size());
    return blob;
}

std::vector<uint8_t> CodeDirectorySigner::buildCodeDirectory(const uint8_t* machOData,
                                                            uint64_t codeLimit,
                                                            const SigningContext& context) {
    constexpr uint8_t HASH_SIZE = 32;       // SHA-256
    constexpr uint8_t HASH_TYPE = 2;        // CS_HASHTYPE_SHA256
    constexpr uint8_t PAGE_SIZE_LOG2 = 12;  // 4096 bytes per page
    const size_t PAGE_SIZE = 1 << PAGE_SIZE_LOG2;

    uint32_t nCodeSlots = static_cast<uint32_t>((codeLimit + PAGE_SIZE - 1) / PAGE_SIZE);
    uint32_t nSpecialSlots = 7; // Slots 1..7 (Info.plist, Requirements, CodeResources, App, Entitlements, RepSpecific, DER)

    std::string ident = context.bundleIdentifier;
    std::string teamID = context.teamIdentifier;

    size_t headerSize = sizeof(CS_CodeDirectoryHeader);
    size_t identOffset = headerSize;
    size_t teamIDOffset = identOffset + ident.length() + 1;
    size_t hashOffset = teamIDOffset + (teamID.empty() ? 0 : teamID.length() + 1);
    // Align hashOffset to 4-byte boundary
    hashOffset = (hashOffset + 3) & ~3;

    // hashOffset points to slot 0. Special slots precede slot 0.
    size_t totalSpecialHashesSize = nSpecialSlots * HASH_SIZE;
    size_t specialHashBase = hashOffset;
    size_t codeHashBase = specialHashBase + totalSpecialHashesSize;
    size_t totalCodeHashesSize = nCodeSlots * HASH_SIZE;
    size_t totalCDSize = codeHashBase + totalCodeHashesSize;

    std::vector<uint8_t> cdBlob(totalCDSize, 0);

    CS_CodeDirectoryHeader* hdr = reinterpret_cast<CS_CodeDirectoryHeader*>(cdBlob.data());
    hdr->magic = htonl(CSMAGIC_CODEDIRECTORY);
    hdr->length = htonl(static_cast<uint32_t>(totalCDSize));
    hdr->version = htonl(0x20400);
    hdr->flags = 0;
    hdr->hashOffset = htonl(static_cast<uint32_t>(codeHashBase));
    hdr->identOffset = htonl(static_cast<uint32_t>(identOffset));
    hdr->nSpecialSlots = htonl(nSpecialSlots);
    hdr->nCodeSlots = htonl(nCodeSlots);
    hdr->codeLimit = htonl(static_cast<uint32_t>(codeLimit));
    hdr->hashSize = HASH_SIZE;
    hdr->hashType = HASH_TYPE;
    hdr->platform = 0;
    hdr->pageSize = PAGE_SIZE_LOG2;
    hdr->spare2 = 0;
    hdr->scatterOffset = 0;
    hdr->teamIDOffset = teamID.empty() ? 0 : htonl(static_cast<uint32_t>(teamIDOffset));
    hdr->spare3 = 0;
    hdr->codeLimit64 = 0;
    hdr->execSegBase = 0;
    hdr->execSegLimit = 0;
    hdr->execSegFlags = 0;

    // Write identifier
    std::memcpy(cdBlob.data() + identOffset, ident.c_str(), ident.length() + 1);

    // Write Team ID if available
    if (!teamID.empty()) {
        std::memcpy(cdBlob.data() + teamIDOffset, teamID.c_str(), teamID.length() + 1);
    }

    // Helper to write special slot hash: slotIndex 1..nSpecialSlots
    auto setSpecialSlot = [&](uint32_t slot, const void* data, size_t len) {
        if (slot > nSpecialSlots) return;
        uint8_t* dest = cdBlob.data() + codeHashBase - (slot * HASH_SIZE);
        if (data && len > 0) {
            sha256_buffer(data, len, dest);
        } else {
            std::memset(dest, 0, HASH_SIZE);
        }
    };

    // Slot 1: Info.plist
    setSpecialSlot(CSSLOT_INFOPLIST, context.infoPlistData.data(), context.infoPlistData.length());

    // Slot 2: Requirements
    std::vector<uint8_t> reqBlob = buildRequirementsBlob(context.bundleIdentifier);
    setSpecialSlot(CSSLOT_REQUIREMENTS, reqBlob.data(), reqBlob.size());

    // Slot 3: CodeResources
    setSpecialSlot(CSSLOT_RESOURCEDIR, context.codeResourcesData.data(), context.codeResourcesData.length());

    // Slot 4: Application
    setSpecialSlot(CSSLOT_APPLICATION, nullptr, 0);

    // Slot 5: Entitlements XML
    if (!context.entitlementsXml.empty()) {
        std::vector<uint8_t> entBlob = buildEntitlementsBlob(context.entitlementsXml);
        setSpecialSlot(CSSLOT_ENTITLEMENTS, entBlob.data(), entBlob.size());
    } else {
        setSpecialSlot(CSSLOT_ENTITLEMENTS, nullptr, 0);
    }

    // Slot 6: Empty
    setSpecialSlot(6, nullptr, 0);

    // Slot 7: DER Entitlements
    if (!context.entitlementsDer.empty()) {
        std::vector<uint8_t> derBlob = buildDerEntitlementsBlob(context.entitlementsDer);
        setSpecialSlot(CSSLOT_DER_ENTITLEMENTS, derBlob.data(), derBlob.size());
    } else {
        setSpecialSlot(CSSLOT_DER_ENTITLEMENTS, nullptr, 0);
    }

    // Hash 4KB Code Pages (Slots 0 to nCodeSlots - 1)
    for (uint32_t i = 0; i < nCodeSlots; ++i) {
        size_t pageOffset = i * PAGE_SIZE;
        size_t pageLength = std::min(PAGE_SIZE, static_cast<size_t>(codeLimit - pageOffset));
        uint8_t* slotDest = cdBlob.data() + codeHashBase + (i * HASH_SIZE);
        sha256_buffer(machOData + pageOffset, pageLength, slotDest);
    }

    return cdBlob;
}

bool CodeDirectorySigner::signBlobCMS(const std::vector<uint8_t>& cdBlob,
                                      const std::vector<uint8_t>& p12Data,
                                      const std::string& p12Password,
                                      std::vector<uint8_t>& cmsBlobWrapper,
                                      std::string& errorString) {
    if (p12Data.empty()) {
        errorString = "Empty PKCS#12 certificate data.";
        return false;
    }

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    BIO* p12Bio = BIO_new_mem_buf(p12Data.data(), static_cast<int>(p12Data.size()));
    if (!p12Bio) {
        errorString = "Failed to allocate memory BIO for PKCS#12.";
        return false;
    }

    PKCS12* p12 = d2i_PKCS12_bio(p12Bio, nullptr);
    BIO_free(p12Bio);

    if (!p12) {
        errorString = "Invalid PKCS#12 format.";
        return false;
    }

    EVP_PKEY* pkey = nullptr;
    X509* cert = nullptr;
    STACK_OF(X509)* caStack = nullptr;

    if (!PKCS12_parse(p12, p12Password.c_str(), &pkey, &cert, &caStack)) {
        PKCS12_free(p12);
        errorString = "PKCS#12 password incorrect or failed to parse credentials.";
        return false;
    }
    PKCS12_free(p12);

    BIO* inBio = BIO_new_mem_buf(cdBlob.data(), static_cast<int>(cdBlob.size()));
    if (!inBio) {
        X509_free(cert);
        EVP_PKEY_free(pkey);
        sk_X509_pop_free(caStack, X509_free);
        errorString = "Failed to allocate BIO for CodeDirectory.";
        return false;
    }

    // Apple CMS signature flags: detached signature over binary content
    int flags = CMS_NOSMIMECAP | CMS_BINARY | CMS_PARTIAL | CMS_DETACHED;
    CMS_ContentInfo* cms = CMS_sign(nullptr, nullptr, nullptr, inBio, flags);
    if (!cms) {
        BIO_free(inBio);
        X509_free(cert);
        EVP_PKEY_free(pkey);
        sk_X509_pop_free(caStack, X509_free);
        errorString = "Failed to initialize CMS structure.";
        return false;
    }

    CMS_SignerInfo* si = CMS_add1_signer(cms, cert, pkey, EVP_sha256(), CMS_NOSMIMECAP | CMS_BINARY);
    if (!si) {
        CMS_ContentInfo_free(cms);
        BIO_free(inBio);
        X509_free(cert);
        EVP_PKEY_free(pkey);
        sk_X509_pop_free(caStack, X509_free);
        errorString = "Failed to add CMS signer info.";
        return false;
    }

    if (caStack) {
        for (int i = 0; i < sk_X509_num(caStack); ++i) {
            CMS_add0_cert(cms, sk_X509_value(caStack, i));
        }
    }

    if (!CMS_final(cms, inBio, nullptr, flags)) {
        CMS_ContentInfo_free(cms);
        BIO_free(inBio);
        X509_free(cert);
        EVP_PKEY_free(pkey);
        sk_X509_pop_free(caStack, X509_free);
        errorString = "Failed to finalize CMS signature.";
        return false;
    }

    BIO* outBio = BIO_new(BIO_s_mem());
    if (i2d_CMS_bio(outBio, cms) <= 0) {
        BIO_free(outBio);
        CMS_ContentInfo_free(cms);
        BIO_free(inBio);
        X509_free(cert);
        EVP_PKEY_free(pkey);
        sk_X509_pop_free(caStack, X509_free);
        errorString = "Failed to serialize CMS DER representation.";
        return false;
    }

    BUF_MEM* memPtr = nullptr;
    BIO_get_mem_ptr(outBio, &memPtr);

    size_t derLen = memPtr->length;
    size_t totalWrapperLen = sizeof(CS_BlobHeader) + derLen;
    cmsBlobWrapper.resize(totalWrapperLen);

    CS_BlobHeader* wrapperHeader = reinterpret_cast<CS_BlobHeader*>(cmsBlobWrapper.data());
    wrapperHeader->magic = htonl(CSMAGIC_BLOBWRAPPER);
    wrapperHeader->length = htonl(static_cast<uint32_t>(totalWrapperLen));
    std::memcpy(cmsBlobWrapper.data() + sizeof(CS_BlobHeader), memPtr->data, derLen);

    BIO_free(outBio);
    CMS_ContentInfo_free(cms);
    BIO_free(inBio);
    X509_free(cert);
    EVP_PKEY_free(pkey);
    sk_X509_pop_free(caStack, X509_free);

    return true;
}

bool CodeDirectorySigner::generateSuperBlob(const uint8_t* machOData,
                                           uint64_t codeLimit,
                                           const SigningContext& context,
                                           std::vector<uint8_t>& outputSuperBlob,
                                           std::string& errorString) {
    std::vector<uint8_t> cdBlob = buildCodeDirectory(machOData, codeLimit, context);
    std::vector<uint8_t> reqBlob = buildRequirementsBlob(context.bundleIdentifier);
    std::vector<uint8_t> entBlob = context.entitlementsXml.empty() ? std::vector<uint8_t>() : buildEntitlementsBlob(context.entitlementsXml);
    std::vector<uint8_t> derBlob = context.entitlementsDer.empty() ? std::vector<uint8_t>() : buildDerEntitlementsBlob(context.entitlementsDer);

    std::vector<uint8_t> cmsBlobWrapper;
    if (!signBlobCMS(cdBlob, context.p12Data, context.p12Password, cmsBlobWrapper, errorString)) {
        return false;
    }

    struct BlobEntry {
        uint32_t slot;
        const std::vector<uint8_t>* data;
    };

    std::vector<BlobEntry> blobs;
    blobs.push_back({CSSLOT_CODEDIRECTORY, &cdBlob});
    blobs.push_back({CSSLOT_REQUIREMENTS, &reqBlob});
    if (!entBlob.empty()) blobs.push_back({CSSLOT_ENTITLEMENTS, &entBlob});
    if (!derBlob.empty()) blobs.push_back({CSSLOT_DER_ENTITLEMENTS, &derBlob});
    blobs.push_back({CSSLOT_SIGNATURESLOT, &cmsBlobWrapper});

    uint32_t count = static_cast<uint32_t>(blobs.size());
    size_t headerSize = sizeof(CS_BlobHeader) + 4 + (count * sizeof(CS_BlobIndex));

    size_t currentOffset = headerSize;
    std::vector<size_t> offsets;
    offsets.reserve(count);

    for (const auto& b : blobs) {
        // 16-byte alignment per sub-blob
        currentOffset = (currentOffset + 15) & ~15;
        offsets.push_back(currentOffset);
        currentOffset += b.data->size();
    }

    outputSuperBlob.assign(currentOffset, 0);

    CS_BlobHeader* superHdr = reinterpret_cast<CS_BlobHeader*>(outputSuperBlob.data());
    superHdr->magic = htonl(CSMAGIC_EMBEDDED_SIGNATURE);
    superHdr->length = htonl(static_cast<uint32_t>(currentOffset));
    *reinterpret_cast<uint32_t*>(outputSuperBlob.data() + sizeof(CS_BlobHeader)) = htonl(count);

    CS_BlobIndex* indices = reinterpret_cast<CS_BlobIndex*>(outputSuperBlob.data() + sizeof(CS_BlobHeader) + 4);
    for (size_t i = 0; i < count; ++i) {
        indices[i].type = htonl(blobs[i].slot);
        indices[i].offset = htonl(static_cast<uint32_t>(offsets[i]));
        std::memcpy(outputSuperBlob.data() + offsets[i], blobs[i].data->data(), blobs[i].data->size());
    }

    return true;
}

} // namespace KSign
