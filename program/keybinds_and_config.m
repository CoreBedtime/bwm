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

extern CGFloat gWindowForce;
extern CGFloat gWindowGap;
extern bool gDisableShadows;
extern int gAnimationStyle;
extern int gTitlebarHeight;
extern bool gTitleOrIcon;
extern bool gButtonPos;

extern int gPaddingLeft, gPaddingRight, gPaddingTop, gPaddingBottom; 


#define LOAD_BOOL(dict, key, var) \
    do { \
        id _val = dict[key]; \
        if ([_val isKindOfClass:[NSNumber class]]) { \
            var = [_val boolValue]; \
        } \
    } while (0)

#define LOAD_INT(dict, key, var) \
    do { \
        id _val = dict[key]; \
        if ([_val isKindOfClass:[NSNumber class]]) { \
            var = [_val intValue]; \
        } \
    } while (0)

#define LOAD_DOUBLE(dict, key, var) \
    do { \
        id _val = dict[key]; \
        if ([_val isKindOfClass:[NSNumber class]]) { \
            var = [_val doubleValue]; \
        } \
    } while (0)


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

    LOAD_DOUBLE(visualsDict, @"gap", gWindowGap);
    gWindowGap = MAX(0, gWindowGap);

    LOAD_DOUBLE(visualsDict, @"spring_animation_force", gWindowForce);
    gWindowForce = MAX(0, gWindowForce);

    LOAD_INT(visualsDict, @"animationstyle", gAnimationStyle);
    LOAD_INT(visualsDict, @"titlebarheight", gTitlebarHeight);
    
    LOAD_INT(visualsDict, @"padding_left", gPaddingLeft);
    LOAD_INT(visualsDict, @"padding_right", gPaddingRight);
    LOAD_INT(visualsDict, @"padding_top", gPaddingTop);
    LOAD_INT(visualsDict, @"padding_bottom", gPaddingBottom);

    LOAD_BOOL(visualsDict, @"shadows", gDisableShadows);
    LOAD_BOOL(visualsDict, @"title_or_icon", gTitleOrIcon);
    LOAD_BOOL(visualsDict, @"button_position", gButtonPos);


    return true; // Settings loaded successfully (or defaults used)
}
