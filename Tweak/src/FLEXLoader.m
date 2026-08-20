#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// FLEXLoader: A lightweight loader dylib that checks user preferences
// and conditionally loads the full FLEX.dylib into the current process.

static BOOL g_flexLoaded = NO;

static BOOL shouldLoadFLEXForCurrentApp(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID) return NO;
    
    // Don't inject into the Settings app or the preferences daemon
    if ([bundleID isEqualToString:@"com.apple.Preferences"]) return NO;
    if ([bundleID isEqualToString:@"com.apple.springboard"]) return NO;
    
    // Read preferences
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.flex.flex64e.plist"];
    
    if (!prefs) return NO;
    
    // Check global kill switch
    NSNumber *globalEnabled = prefs[@"globalEnabled"];
    if (globalEnabled && ![globalEnabled boolValue]) return NO;
    
    // Check per-app toggle (AltList uses the key as a prefix at the root of the plist)
    NSString *appKey = [NSString stringWithFormat:@"enabledApps-%@", bundleID];
    NSNumber *appEnabled = prefs[appKey];
    if (!appEnabled) return NO;
    
    return [appEnabled boolValue];
}

static void loadFLEX(void) {
    if (g_flexLoaded) return;
    
    // Try multiple possible paths for the FLEX dylib
    NSArray *paths = @[
        @"/Library/MobileSubstrate/DynamicLibraries/FLEX.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/FLEX.dylib",
    ];
    
    void *handle = NULL;
    for (NSString *path in paths) {
        handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        if (handle) break;
    }
    
    if (!handle) {
        NSLog(@"[FLEX64e] Failed to load FLEX.dylib: %s", dlerror());
        return;
    }
    
    g_flexLoaded = YES;
    NSLog(@"[FLEX64e] FLEX.dylib loaded successfully for %@", 
          NSBundle.mainBundle.bundleIdentifier);
}

static void showFLEXToolbar(void) {
    // Get FLEXManager and show the explorer
    Class FLEXManager = NSClassFromString(@"FLEXManager");
    if (!FLEXManager) {
        NSLog(@"[FLEX64e] FLEXManager class not found after loading dylib");
        return;
    }
    
    id manager = [FLEXManager performSelector:@selector(sharedManager)];
    if (manager) {
        [manager performSelector:@selector(showExplorer)];
        NSLog(@"[FLEX64e] Explorer toolbar shown");
    }
}

// Hook into the app lifecycle to show FLEX after the UI is ready
__attribute__((constructor))
static void FLEXLoaderInit(void) {
    @autoreleasepool {
        if (!shouldLoadFLEXForCurrentApp()) return;
        
        loadFLEX();
        
        if (!g_flexLoaded) return;
        
        // Wait for the app to finish launching before showing the toolbar
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                // Small delay to ensure windows are set up
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 
                    (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    showFLEXToolbar();
                });
            }
        ];
    }
}
