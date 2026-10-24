// SPDX-License-Identifier: GPL-3.0-only
#import "LauncherConfig.h"
#import "GameLocation.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <os/log.h>
#import <string.h>

static NSURL *targetApplicationURL(void) {
    return DI2GameURLBesideLauncher(NSBundle.mainBundle.bundleURL);
}
static void fail(NSString *message) {
    os_log_error(OS_LOG_DEFAULT, "DeadIsland2 launcher error: %{public}s", message.UTF8String);
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Dead Island 2 Starthelfer";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}
static OSStatus validateOriginalApplication(NSURL *target) {
    SecStaticCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)target, kSecCSDefaultFlags, &code);
    if (status == errSecSuccess) {
        status = SecRequirementCreateWithString(
            CFSTR("anchor apple generic and identifier \"" DI2_ORIGINAL_BUNDLE_ID "\""),
            kSecCSDefaultFlags, &requirement);
    }
    if (status == errSecSuccess) {
        status = SecStaticCodeCheckValidity(code,
            kSecCSDoNotValidateResources | kSecCSCheckAllArchitectures, requirement);
    }
    if (status == errSecSuccess) {
        CFDictionaryRef information = NULL;
        status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information);
        NSDictionary *details = CFBridgingRelease(information);
        NSString *team = details[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
        if (status == errSecSuccess && ![team isEqualToString:@DI2_MANUFACTURER_TEAM_ID]) {
            status = errSecCSReqFailed;
        }
    }
    if (code) {
        CFRelease(code);
    }
    if (requirement) {
        CFRelease(requirement);
    }
    return status;
}
@interface LauncherDelegate : NSObject <NSApplicationDelegate>
@end
@implementation LauncherDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSURL *target = targetApplicationURL();
    NSBundle *game = [NSBundle bundleWithURL:target];
    if (![game.bundleIdentifier isEqualToString:@DI2_ORIGINAL_BUNDLE_ID]) {
        fail([NSString stringWithFormat:
            @"Lege die unveränderte App-Store-Version DeadIsland2.app mit der Kennung "
             "com.plaion.DeadIsland2Usk in denselben Ordner wie diesen Starthelfer. "
             "Gesucht wird: %@", target.path]);
        [NSApp terminate:nil]; return;
    }
    for (NSRunningApplication *running in NSWorkspace.sharedWorkspace.runningApplications) {
        if (DI2URLsReferToSameFile(running.bundleURL, target)) {
            fail(@"Bitte beende zuerst die laufende App-Store-Version und starte danach diesen Helfer erneut. Laufende Spiele werden nicht automatisch beendet.");
            [NSApp terminate:nil]; return;
        }
    }
    OSStatus status = validateOriginalApplication(target);
    if (status != errSecSuccess) {
        fail([NSString stringWithFormat:@"Die Original-Herstellersignatur konnte nicht bestätigt werden (Fehler %d). Die Spiele-App wurde nicht verändert.", (int)status]);
        [NSApp terminate:nil]; return;
    }
    NSString *library = [NSBundle.mainBundle pathForResource:@"RuntimeIdentity" ofType:@"dylib"];
    if (!library) {
        fail(@"Das externe Hilfsmodul fehlt.");
        [NSApp terminate:nil];
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = NSWorkspaceOpenConfiguration.configuration;
    configuration.activates = YES;
    configuration.createsNewApplicationInstance = YES;
    NSMutableDictionary *environment = [@{@"DYLD_INSERT_LIBRARIES": library} mutableCopy];
    if ([NSProcessInfo.processInfo.environment[@DI2_CLOUD_CHECK_ENV] isEqualToString:@"1"]) {
        environment[@DI2_CLOUD_CHECK_ENV] = @"1";
    }
    configuration.environment = environment;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:target configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                fail([NSString stringWithFormat:@"Das Spiel konnte nicht gestartet werden: %@",
                    error.localizedDescription]);
            } else {
                os_log(OS_LOG_DEFAULT,
                    "DeadIsland2 external launcher submitted original App Store process pid=%{public}d",
                    app.processIdentifier);
            }
            [NSApp terminate:nil];
        });
    }];
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--game-path") == 0) {
            puts(targetApplicationURL().path.fileSystemRepresentation);
            return 0;
        }
        if ((argc == 2 || argc == 3) && strcmp(argv[1], "--validate-only") == 0) {
            // An explicit path is for read-only build validation; launch always
            // selects the adjacent app.
            NSURL *target = argc == 3
                ? [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES]
                : targetApplicationURL();
            OSStatus result = validateOriginalApplication(target);
            printf("Original App Store signature / identifier / signed team: %d\n", (int)result);
            return result == errSecSuccess ? 0 : 2;
        }
        NSApplication *application = NSApplication.sharedApplication;
        LauncherDelegate *delegate = [LauncherDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
