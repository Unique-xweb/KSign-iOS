// [LISTN] Sources/CoreSignEngine/include/CoreSignEngine.h
// Language: Objective-C | File: CoreSignEngine.h | Target: Swift-to-C++ Code Signing Bridge
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CoreSignEngine : NSObject

/// Signs a Mach-O binary (executable, framework, or dylib) with a PKCS#12 certificate
+ (BOOL)signBinaryAtPath:(NSString *)binaryPath
                bundleID:(NSString *)bundleID
                  teamID:(nullable NSString *)teamID
          infoPlistData:(nullable NSData *)infoPlistData
     codeResourcesData:(nullable NSData *)codeResourcesData
       entitlementsXml:(nullable NSString *)entitlementsXml
       entitlementsDer:(nullable NSData *)entitlementsDer
               p12Data:(NSData *)p12Data
           p12Password:(NSString *)p12Password
                 error:(NSError * _Nullable *)error;

/// Injects a dylib load command (LC_LOAD_DYLIB) into the target Mach-O binary
+ (BOOL)injectDylibAtPath:(NSString *)dylibPath
         intoBinaryAtPath:(NSString *)binaryPath
                   isWeak:(BOOL)isWeak
                    error:(NSError * _Nullable *)error;

/// Inspects architecture slices and signature boundaries of a Mach-O binary
+ (nullable NSDictionary<NSString *, id> *)inspectMachOAtPath:(NSString *)binaryPath
                                                        error:(NSError * _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
