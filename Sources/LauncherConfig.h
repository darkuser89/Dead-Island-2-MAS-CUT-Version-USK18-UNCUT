// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#define DI2_GAME_APP_PATH "/Applications/DeadIsland2.app"
#define DI2_GAME_EXECUTABLE_PATH DI2_GAME_APP_PATH "/Contents/MacOS/DeadIsland2"
#define DI2_ORIGINAL_BUNDLE_ID "com.plaion.DeadIsland2Usk"
#define DI2_RUNTIME_BUNDLE_ID "com.plaion.DeadIsland2"
#define DI2_MANUFACTURER_TEAM_ID "XSBJ2Q9R2T"
#define DI2_CLOUD_CONTAINER_ID "iCloud.com.plaion.DeadIsland2"
#define DI2_PROBE_BUNDLE_ID "local.deadisland2.runtime-probe"
#define DI2_CLOUD_CHECK_ENV "DI2_LAUNCHER_CLOUD_CHECK"

// Retains the dictionary used by the tested runtime approach. This value alone
// was not sufficient when written into a game Info.plist.
#define DI2_RUNTIME_SKU "LocalUncut-@ADMOJA@D@"
