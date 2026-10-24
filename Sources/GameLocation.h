// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#import "LauncherConfig.h"
#import <Foundation/Foundation.h>
#import <sys/stat.h>

// Resolve relative to the launcher bundle, never to the current directory or
// LaunchServices registration of another installed copy.
static inline NSURL *DI2GameURLBesideLauncher(NSURL *launcherURL) {
    NSURL *directory = launcherURL.URLByResolvingSymlinksInPath.URLByDeletingLastPathComponent;
    return [directory URLByAppendingPathComponent:@DI2_GAME_APP_NAME isDirectory:YES]
        .URLByResolvingSymlinksInPath;
}

// File identity also handles symlinks and canonically equivalent Unicode names.
static inline BOOL DI2URLsReferToSameFile(NSURL *left, NSURL *right) {
    struct stat leftInfo = {0};
    struct stat rightInfo = {0};
    return left && right
        && stat(left.path.fileSystemRepresentation, &leftInfo) == 0
        && stat(right.path.fileSystemRepresentation, &rightInfo) == 0
        && leftInfo.st_dev == rightInfo.st_dev
        && leftInfo.st_ino == rightInfo.st_ino;
}
