// [LISTN] Sources/CoreSignEngine/CoreSignEngine.mm
// Language: Objective-C++ | File: CoreSignEngine.mm | Target: Swift-to-C++ Code Signing Bridge
#import "CoreSignEngine.h"
#import "MachOModifier.h"
#import "CodeDirectorySigner.h"

#include <vector>
#include <string>

static NSError *MakeError(NSString *description, NSInteger code = -1) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: description ?: @"Unknown Code Signing Error"};
    return [NSError errorWithDomain:@"com.ksign.engine" code:code userInfo:userInfo];
}

@implementation CoreSignEngine

+ (BOOL)signBinaryAtPath:(NSString *)binaryPath
                bundleID:(NSString *)bundleID
                  teamID:(nullable NSString *)teamID
          infoPlistData:(nullable NSData *)infoPlistData
     codeResourcesData:(nullable NSData *)codeResourcesData
       entitlementsXml:(nullable NSString *)entitlementsXml
       entitlementsDer:(nullable NSData *)entitlementsDer
               p12Data:(NSData *)p12Data
           p12Password:(NSString *)p12Password
                 error:(NSError * _Nullable *)error {
    if (!binaryPath || !bundleID || !p12Data || !p12Password) {
        if (error) *error = MakeError(@"Missing mandatory signing parameters.");
        return NO;
    }

    std::string path([binaryPath UTF8String]);
    KSign::MachOModifier modifier(path);

    if (!modifier.load()) {
        if (error) *error = MakeError([NSString stringWithFormat:@"Failed to load Mach-O binary at %@", binaryPath]);
        return NO;
    }

    const auto& slices = modifier.getSlices();
    if (slices.empty()) {
        if (error) *error = MakeError(@"No valid Mach-O architecture slices found in binary.");
        return NO;
    }

    KSign::SigningContext ctx;
    ctx.bundleIdentifier = [bundleID UTF8String];
    ctx.teamIdentifier = teamID ? [teamID UTF8String] : "";

    if (infoPlistData) {
        ctx.infoPlistData = std::string(reinterpret_cast<const char *>(infoPlistData.bytes), infoPlistData.length);
    }
    if (codeResourcesData) {
        ctx.codeResourcesData = std::string(reinterpret_cast<const char *>(codeResourcesData.bytes), codeResourcesData.length);
    }
    if (entitlementsXml) {
        ctx.entitlementsXml = [entitlementsXml UTF8String];
    }
    if (entitlementsDer) {
        const uint8_t *bytes = reinterpret_cast<const uint8_t *>(entitlementsDer.bytes);
        ctx.entitlementsDer.assign(bytes, bytes + entitlementsDer.length);
    }

    const uint8_t *p12Bytes = reinterpret_cast<const uint8_t *>(p12Data.bytes);
    ctx.p12Data.assign(p12Bytes, p12Bytes + p12Data.length);
    ctx.p12Password = [p12Password UTF8String];

    KSign::CodeDirectorySigner signer;

    for (const auto& slice : slices) {
        uint32_t oldCsOffset = 0;
        uint32_t oldCsSize = 0;
        uint64_t codeLimit = slice.fileSize;

        if (modifier.getCodeSignatureOffsetAndSize(slice.fileOffset, oldCsOffset, oldCsSize)) {
            if (oldCsOffset > 0) {
                codeLimit = oldCsOffset;
            }
        }

        const uint8_t *slicePtr = modifier.getRawData().data() + slice.fileOffset;
        std::vector<uint8_t> superBlob;
        std::string errStr;

        if (!signer.generateSuperBlob(slicePtr, codeLimit, ctx, superBlob, errStr)) {
            if (error) {
                NSString *nsErr = [NSString stringWithUTF8String:errStr.c_str()];
                *error = MakeError(nsErr ?: @"Failed to generate Code Directory and CMS SuperBlob.");
            }
            return NO;
        }

        if (!modifier.updateCodeSignature(slice.fileOffset, superBlob)) {
            if (error) *error = MakeError(@"Failed to write SuperBlob into Mach-O __LINKEDIT segment.");
            return NO;
        }
    }

    if (!modifier.save()) {
        if (error) *error = MakeError(@"Failed to persist signed Mach-O binary back to disk.");
        return NO;
    }

    return YES;
}

+ (BOOL)injectDylibAtPath:(NSString *)dylibPath
         intoBinaryAtPath:(NSString *)binaryPath
                   isWeak:(BOOL)isWeak
                    error:(NSError * _Nullable *)error {
    if (!dylibPath || !binaryPath) {
        if (error) *error = MakeError(@"Invalid dylib path or binary path.");
        return NO;
    }

    KSign::MachOModifier modifier([binaryPath UTF8String]);
    if (!modifier.load()) {
        if (error) *error = MakeError(@"Failed to open Mach-O binary for dylib injection.");
        return NO;
    }

    if (!modifier.injectDylib([dylibPath UTF8String], isWeak)) {
        if (error) *error = MakeError(@"Failed to inject LC_LOAD_DYLIB. Binary header may have insufficient padding.");
        return NO;
    }

    if (!modifier.save()) {
        if (error) *error = MakeError(@"Failed to save modified Mach-O binary after injection.");
        return NO;
    }

    return YES;
}

+ (nullable NSDictionary<NSString *, id> *)inspectMachOAtPath:(NSString *)binaryPath
                                                        error:(NSError * _Nullable *)error {
    KSign::MachOModifier modifier([binaryPath UTF8String]);
    if (!modifier.load()) {
        if (error) *error = MakeError(@"Cannot inspect invalid Mach-O file.");
        return nil;
    }

    NSMutableArray *slicesArray = [NSMutableArray array];
    for (const auto& slice : modifier.getSlices()) {
        uint32_t csOff = 0;
        uint32_t csSize = 0;
        BOOL hasSig = modifier.getCodeSignatureOffsetAndSize(slice.fileOffset, csOff, csSize);

        [slicesArray addObject:@{
            @"cpuType": @(slice.cpuType),
            @"cpuSubtype": @(slice.cpuSubtype),
            @"fileOffset": @(slice.fileOffset),
            @"fileSize": @(slice.fileSize),
            @"is64Bit": @(slice.is64Bit),
            @"hasSignature": @(hasSig),
            @"csOffset": @(csOff),
            @"csSize": @(csSize)
        }];
    }

    return @{
        @"path": binaryPath,
        @"slicesCount": @(slicesArray.count),
        @"slices": slicesArray
    };
}

@end
