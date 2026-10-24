// SPDX-License-Identifier: GPL-3.0-only
#import "LauncherConfig.h"
#import <Foundation/Foundation.h>
#import <string.h>
extern NSString *frameworkBundleIdentifier(void);
extern NSString *frameworkDictionaryIdentifier(void);
extern NSString *frameworkObjectIdentifier(void);
extern NSString *frameworkSKU(void);
extern NSString *frameworkIdentifierForBundle(NSBundle *bundle);
static BOOL equalValues(id left, id right) {
    return left == right || [left isEqual:right];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL expectOverride = !(argc == 2 && strcmp(argv[1], "--expect-inactive") == 0);
        NSBundle *bundle = NSBundle.mainBundle;
        NSURL *infoURL = [bundle.bundleURL URLByAppendingPathComponent:@"Contents/Info.plist"];
        NSDictionary *diskInfo = [NSPropertyListSerialization
            propertyListWithData:[NSData dataWithContentsOfURL:infoURL]
            options:0 format:NULL error:NULL];
        NSString *diskIdentifier = diskInfo[@"CFBundleIdentifier"];
        NSString *expectedIdentifier = expectOverride ? @DI2_RUNTIME_BUNDLE_ID : diskIdentifier;
        NSString *expectedSKU = expectOverride ? @DI2_RUNTIME_SKU : diskInfo[@"USKVersion"];
        NSArray *gameValues = @[bundle.bundleIdentifier, bundle.infoDictionary[@"CFBundleIdentifier"], [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"]];
        NSArray *frameworkValues = @[frameworkBundleIdentifier(), frameworkDictionaryIdentifier(), frameworkObjectIdentifier()];
        for (NSString *value in gameValues) {
            if (![value isEqualToString:expectedIdentifier]) {
                fputs("FAIL: executable received an unexpected identity\n", stderr);
                return 2;
            }
        }
        for (NSString *value in frameworkValues) {
            if (![value isEqualToString:diskIdentifier]) {
                fputs("FAIL: external-image identity was modified\n", stderr);
                return 3;
            }
        }
        if (!equalValues(bundle.infoDictionary[@"USKVersion"], expectedSKU)
            || !equalValues([bundle objectForInfoDictionaryKey:@"USKVersion"], expectedSKU)) {
            fputs("FAIL: executable received an unexpected SKU\n", stderr);
            return 4;
        }
        if (!equalValues(frameworkSKU(), diskInfo[@"USKVersion"])) {
            fputs("FAIL: runtime-only SKU leaked into an external-image call\n", stderr);
            return 5;
        }
        NSBundle *foundation = [NSBundle bundleForClass:NSBundle.class];
        if (![foundation.bundleIdentifier isEqualToString:frameworkIdentifierForBundle(foundation)]
            || [foundation.bundleIdentifier isEqualToString:@DI2_RUNTIME_BUNDLE_ID]) {
            fputs("FAIL: a non-main bundle was modified\n", stderr);
            return 6;
        }
        puts(expectOverride
            ? "PASS: executable identity override; external-image and non-main bundle isolation; SKU isolation"
            : "PASS: unsupported process kept original identity and SKU");
        return 0;
    }
}
