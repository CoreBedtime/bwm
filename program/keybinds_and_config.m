// i will be seperated one day

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Carbon/Carbon.h> 
#import <mach/mach.h>

#import "shared.h"

#define CONFIG_DIR_PATH @"~/.config/bwm"
#define KEYBINDINGS_FILE_NAME @"keybindings.json"
#define VISUALS_FILE_NAME @"visual.json" // <<< ADDED


extern NSDictionary<NSString *, NSNumber *> *GetKeycodeMap();
extern NSMutableArray<NSValue *> *gKeyBindings;

extern CGFloat gWindowGap;
extern bool gDisableShadows;
extern int gAnimationStyle;
extern int gTitlebarHeight;
extern bool gTitleOrIcon;
extern bool gButtonPos;


NSArray * LoadKeyBindings() {
    NSMutableArray * KeyBindings = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *configDir = [CONFIG_DIR_PATH stringByExpandingTildeInPath];
    NSString *configPath = [configDir stringByAppendingPathComponent:KEYBINDINGS_FILE_NAME];

    NSLog(@"[+] Attempting to load keybindings from: %@", configPath);

    if (![fileManager fileExistsAtPath:configPath]) {
        NSLog(@"[!] Warning: Keybindings file not found at %@. Using default or no bindings.", configPath);
        // Optionally create a default config file here
        return NULL; // Not a fatal error, just means no custom bindings
    }

    NSError *error = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:configPath options:0 error:&error];
    if (!jsonData) {
        NSLog(@"[!] Error reading keybindings file: %@", error.localizedDescription);
        return NULL; // File exists but couldn't be read
    }

    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!jsonObject) {
        NSLog(@"[!] Error parsing keybindings JSON: %@", error.localizedDescription);
        return NULL;
    }

    if (![jsonObject isKindOfClass:[NSArray class]]) {
        NSLog(@"[!] Error: Keybindings JSON root object must be an array.");
        return NULL;
    }

    NSArray *bindingsArray = (NSArray *)jsonObject;
    NSDictionary<NSString *, NSNumber *> *keycodeMap = GetKeycodeMap();

    for (id item in bindingsArray) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[!] Warning: Skipping invalid item in keybindings array (not an object).");
            continue;
        }
        NSDictionary *bindingDict = (NSDictionary *)item;

        NSString *keyStr = bindingDict[@"key"];
        NSString *actionStr = bindingDict[@"action"];

        if (!keyStr || ![keyStr isKindOfClass:[NSString class]] || keyStr.length == 0) {
            NSLog(@"[!] Warning: Skipping binding with missing or invalid 'key'.");
            continue;
        }
        if (!actionStr || ![actionStr isKindOfClass:[NSString class]] || actionStr.length == 0) {
            NSLog(@"[!] Warning: Skipping binding with missing or invalid 'action' for key '%@'.", keyStr);
            continue;
        }

        // Map key string to key code
        NSNumber *keyCodeNum = keycodeMap[[keyStr lowercaseString]];
        if (!keyCodeNum) {
            NSLog(@"[!] Warning: Skipping binding for unsupported key string '%@'. Add it to GetKeycodeMap if needed.", keyStr);
            continue;
        }
        CGKeyCode keyCode = [keyCodeNum unsignedShortValue];

        CGEventFlags requiredFlags = kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskCommand;

        // Store the parsed binding
        KeyBinding binding = { .keyCode = keyCode, .requiredFlags = requiredFlags, .action = [actionStr copy] };
        [KeyBindings addObject:[NSValue valueWithBytes:&binding objCType:@encode(KeyBinding)]];
        NSLog(@"[+] Loaded binding: Key=%@ (0x%X), Flags=0x%llX, Action=%@", keyStr, keyCode, requiredFlags, actionStr);
    }

    NSLog(@"[+] Successfully loaded %lu keybindings.", (unsigned long)gKeyBindings.count);
    return KeyBindings.copy;
}

bool LoadVisualSettings() {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *configDir = [CONFIG_DIR_PATH stringByExpandingTildeInPath];
    NSString *configPath = [configDir stringByAppendingPathComponent:VISUALS_FILE_NAME];

    NSLog(@"[+] Attempting to load visual settings from: %@", configPath);

    if (![fileManager fileExistsAtPath:configPath]) {
        NSLog(@"[!] Warning: Visual settings file not found at %@. Using default gap: %.1f", configPath, gWindowGap);
        return true; // Not a fatal error, defaults will be used
    }

    NSError *error = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:configPath options:0 error:&error];
    if (!jsonData) {
        NSLog(@"[!] Error reading visual settings file: %@. Using default gap.", error.localizedDescription);
        // Decide if this should be fatal or just use defaults. Using defaults seems reasonable.
        return true;
    }

    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!jsonObject) {
        NSLog(@"[!] Error parsing visual settings JSON: %@. Using default gap.", error.localizedDescription);
        return true; // Use defaults
    }

    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[!] Error: Visual settings JSON root object must be a dictionary (e.g., {\"gap\": 5}). Using default gap.");
        return true; // Use defaults
    }

    NSDictionary *visualsDict = (NSDictionary *)jsonObject;

    // Load Gap setting
    NSNumber *gapNumber = visualsDict[@"gap"];
    if (gapNumber && [gapNumber isKindOfClass:[NSNumber class]]) {
        gWindowGap = [gapNumber doubleValue];
        if (gWindowGap < 0)
            gWindowGap = 0;
    }

    NSNumber *animStyle = visualsDict[@"animationstyle"];
    if (animStyle && [animStyle isKindOfClass:[NSNumber class]]) {
        gAnimationStyle = [animStyle intValue];
    }

    NSNumber *TitlebarHeight = visualsDict[@"titlebarheight"];
    if (TitlebarHeight && [TitlebarHeight isKindOfClass:[NSNumber class]]) {
        gTitlebarHeight = [TitlebarHeight intValue];
    }

    NSNumber *disableShadowsNumber = visualsDict[@"shadows"];
    if (disableShadowsNumber && [disableShadowsNumber isKindOfClass:[NSNumber class]]) {
        gDisableShadows = [disableShadowsNumber boolValue];
    }

    NSNumber *TitleOrIconVal = visualsDict[@"title_or_icon"];
    if (TitleOrIconVal && [TitleOrIconVal isKindOfClass:[NSNumber class]]) {
        gTitleOrIcon = [TitleOrIconVal boolValue];
    }

    NSNumber *OrientationVal = visualsDict[@"button_position"];
    if (OrientationVal && [OrientationVal isKindOfClass:[NSNumber class]]) {
        gButtonPos = [OrientationVal boolValue];
    }



    return true; // Settings loaded successfully (or defaults used)
}
