// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>
NSString *frameworkBundleIdentifier(void) { return NSBundle.mainBundle.bundleIdentifier; }
NSString *frameworkDictionaryIdentifier(void) { return NSBundle.mainBundle.infoDictionary[@"CFBundleIdentifier"]; }
NSString *frameworkObjectIdentifier(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIdentifier"]; }
NSString *frameworkSKU(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"USKVersion"]; }
NSString *frameworkIdentifierForBundle(NSBundle *bundle) { return bundle.bundleIdentifier; }
