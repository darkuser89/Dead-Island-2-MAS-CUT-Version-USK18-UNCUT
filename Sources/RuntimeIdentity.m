// SPDX-License-Identifier: GPL-3.0-only
#import "LauncherConfig.h"
#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>
#import <Security/SecTask.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <os/log.h>
#import <limits.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>

static NSBundle *mainBundle;
static NSDictionary *gameInfo;
static NSString *realIdentifier;
static NSString *const gameIdentifier = @DI2_RUNTIME_BUNDLE_ID;
static NSString *const originalIdentifier = @DI2_ORIGINAL_BUNDLE_ID;
static NSString *const probeIdentifier = @DI2_PROBE_BUNDLE_ID;
static os_log_t auditLog;
static NSString *(*originalBundleIdentifier)(id, SEL);
static NSDictionary *(*originalInfoDictionary)(id, SEL);
static id (*originalObjectForKey)(id, SEL, NSString *);
static BOOL probeMode;
static const struct mach_header *executableHeader;

static BOOL callerIsExecutable(void *address) {
    Dl_info image = {0};
    BOOL known = address && dladdr(address, &image);
    return known && image.dli_fbase == executableHeader;
}

__attribute__((noinline))
static NSString *runtimeBundleIdentifier(NSBundle *self, SEL selector) {
    void *caller = __builtin_extract_return_addr(__builtin_return_address(0));
    NSString *actual = originalBundleIdentifier(self, selector);
    if (self == mainBundle && callerIsExecutable(caller)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            os_log(auditLog, "GAME bundleIdentifier override active; disk/signing identity unchanged");
        });
        return gameIdentifier;
    }
    return actual;
}

__attribute__((noinline))
static NSDictionary *runtimeInfoDictionary(NSBundle *self, SEL selector) {
    void *caller = __builtin_extract_return_addr(__builtin_return_address(0));
    if (self == mainBundle && callerIsExecutable(caller)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            os_log(auditLog, "GAME infoDictionary override active; original dictionary retained for frameworks");
        });
        return gameInfo;
    }
    return originalInfoDictionary(self, selector);
}

__attribute__((noinline))
static id runtimeObjectForKey(NSBundle *self, SEL selector, NSString *key) {
    void *caller = __builtin_extract_return_addr(__builtin_return_address(0));
    if (self == mainBundle && callerIsExecutable(caller)) {
        if ([key isEqualToString:@"CFBundleIdentifier"]) {
            return gameIdentifier;
        }
        if ([key isEqualToString:@"USKVersion"]) {
            return gameInfo[key];
        }
    }
    return originalObjectForKey(self, selector, key);
}

static void checkCloudKit(void) {
    @autoreleasepool {
        SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        CFErrorRef taskError = NULL;
        CFTypeRef value = task ? SecTaskCopyValueForEntitlement(
            task, CFSTR("com.apple.developer.icloud-container-identifiers"), &taskError) : NULL;
        NSArray *containers = CFBridgingRelease(value);
        BOOL allowed = [containers isKindOfClass:NSArray.class]
            && [containers containsObject:@DI2_CLOUD_CONTAINER_ID];
        if (task) {
            CFRelease(task);
        }
        if (taskError) {
            CFRelease(taskError);
        }
        os_log(auditLog, "CLOUD authoritative container entitlement present=%{public}d; native bundle identifier=%{public}s", allowed, realIdentifier.UTF8String);
        if (!allowed) {
            return;
        }
        @try {
            CKContainer *container = [CKContainer containerWithIdentifier:@DI2_CLOUD_CONTAINER_ID];
            [container accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError *error) {
                os_log(auditLog, "CLOUD account status=%{public}ld error=%{public}s/%{public}ld", (long)status, (error.domain ?: @"none").UTF8String, (long)error.code);
                if (status != CKAccountStatusAvailable || error) {
                    return;
                }
                [container.privateCloudDatabase fetchAllRecordZonesWithCompletionHandler:^(NSArray<CKRecordZone *> *zones, NSError *zoneError) {
                    os_log(auditLog, "CLOUD private database read completed success=%{public}d zones=%{public}lu error=%{public}s/%{public}ld; no cloud writes requested", zoneError == nil, (unsigned long)zones.count, (zoneError.domain ?: @"none").UTF8String, (long)zoneError.code);
                }];
            }];
        } @catch (NSException *exception) {
            os_log_error(auditLog, "CLOUD diagnostic exception=%{public}s", exception.name.UTF8String);
        }
    }
}

__attribute__((constructor))
static void installRuntimeIdentity(void) {
    @autoreleasepool {
        auditLog = os_log_create("local.deadisland2.launcher", "runtime");
        uint32_t size = PATH_MAX;
        char executable[PATH_MAX] = {0};
        if (_NSGetExecutablePath(executable, &size) != 0) {
            return;
        }
        char canonical[PATH_MAX] = {0};
        if (!realpath(executable, canonical)) {
            return;
        }
        mainBundle = NSBundle.mainBundle;
        realIdentifier = [mainBundle.bundleIdentifier copy];
        probeMode = [realIdentifier isEqualToString:probeIdentifier]
            && strcmp(strrchr(canonical, '/') + 1, "RuntimeProbe") == 0;
        BOOL game = strcmp(canonical, DI2_GAME_EXECUTABLE_PATH) == 0
            && [realIdentifier isEqualToString:originalIdentifier];
        if (!game && !probeMode) {
            os_log_error(auditLog, "REFUSED unsupported process; no hooks installed");
            return;
        }
        // An inserted dylib may occupy image index zero. Identify MH_EXECUTE
        // instead of assuming that the first dyld image is the game.
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (header && header->filetype == MH_EXECUTE) {
                executableHeader = header;
                break;
            }
        }
        if (!executableHeader) {
            return;
        }
        NSDictionary *actualInfo = mainBundle.infoDictionary;
        NSMutableDictionary *copy = [actualInfo mutableCopy];
        copy[@"CFBundleIdentifier"] = gameIdentifier;
        copy[@"USKVersion"] = @DI2_RUNTIME_SKU;
        gameInfo = [copy copy];
        Method identifierMethod = class_getInstanceMethod(NSBundle.class, @selector(bundleIdentifier));
        Method infoMethod = class_getInstanceMethod(NSBundle.class, @selector(infoDictionary));
        Method objectMethod = class_getInstanceMethod(NSBundle.class, @selector(objectForInfoDictionaryKey:));
        if (!identifierMethod || !infoMethod || !objectMethod) {
            return;
        }
        // Publish all original IMPs before any replacement can be called.
        originalBundleIdentifier = (void *)method_getImplementation(identifierMethod);
        originalInfoDictionary = (void *)method_getImplementation(infoMethod);
        originalObjectForKey = (void *)method_getImplementation(objectMethod);
        method_setImplementation(identifierMethod, (IMP)runtimeBundleIdentifier);
        method_setImplementation(infoMethod, (IMP)runtimeInfoDictionary);
        method_setImplementation(objectMethod, (IMP)runtimeObjectForKey);
        os_log(auditLog, "READY runtime identity helper loaded; original=%{public}s probe=%{public}d; no app file writes", realIdentifier.UTF8String, probeMode);
        BOOL cloudCheck = [NSProcessInfo.processInfo.environment[@DI2_CLOUD_CHECK_ENV]
            isEqualToString:@"1"];
        if (!probeMode && cloudCheck) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ checkCloudKit(); });
        }
    }
}
