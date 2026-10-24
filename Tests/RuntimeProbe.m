// SPDX-License-Identifier: GPL-3.0-only
#import "LauncherConfig.h"
#import <Foundation/Foundation.h>
extern NSString *frameworkBundleIdentifier(void);
extern NSString *frameworkDictionaryIdentifier(void);
extern NSString *frameworkObjectIdentifier(void);
extern NSString *frameworkSKU(void);
extern NSString *frameworkIdentifierForBundle(NSBundle *bundle);
int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSArray *gameValues = @[bundle.bundleIdentifier, bundle.infoDictionary[@"CFBundleIdentifier"], [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"]];
        NSArray *frameworkValues = @[frameworkBundleIdentifier(), frameworkDictionaryIdentifier(), frameworkObjectIdentifier()];
        for (NSString *value in gameValues) {
            if (![value isEqualToString:@DI2_RUNTIME_BUNDLE_ID]) {
                fputs("FAIL: executable call did not receive the runtime identity\n", stderr);
                return 2;
            }
        }
        for (NSString *value in frameworkValues) {
            if (![value isEqualToString:@DI2_PROBE_BUNDLE_ID]) {
                fputs("FAIL: external-image identity was modified\n", stderr);
                return 3;
            }
        }
        if (![bundle.infoDictionary[@"USKVersion"] isEqualToString:@DI2_RUNTIME_SKU]) {
            return 4;
        }
        if (frameworkSKU() != nil) {
            fputs("FAIL: runtime-only SKU leaked into an external-image call\n", stderr);
            return 5;
        }
        NSBundle *foundation = [NSBundle bundleForClass:NSBundle.class];
        if (![foundation.bundleIdentifier isEqualToString:frameworkIdentifierForBundle(foundation)]
            || [foundation.bundleIdentifier isEqualToString:@DI2_RUNTIME_BUNDLE_ID]) {
            fputs("FAIL: a non-main bundle was modified\n", stderr);
            return 6;
        }
        puts("PASS: executable identity override; external-image and non-main bundle isolation; SKU isolation");
        return 0;
    }
}
