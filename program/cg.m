#include <ColorSync/ColorSync.h> /// ??? what
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>

#import "cfmacro.h"

extern CGError SLSGetWindowOwner(int cid, uint32_t wid, int* out_cid);
extern CGError SLSConnectionGetPID(int cid, pid_t *pid);
extern CFArrayRef SLSCopyWindowsWithOptionsAndTags(int cid, uint32_t owner, CFArrayRef spaces, uint32_t options, uint64_t *set_tags, uint64_t *clear_tags);
extern CFTypeRef SLSWindowQueryWindows(int cid, CFArrayRef windows, uint32_t options);
extern CFTypeRef SLSWindowQueryResultCopyWindows(CFTypeRef window_query);
extern int SLSWindowIteratorGetCount(CFTypeRef iterator);
extern bool SLSWindowIteratorAdvance(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetParentID(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetWindowID(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetTags(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetAttributes(CFTypeRef iterator);
extern CFStringRef SLSCopyBestManagedDisplayForPoint(int cid, CGPoint point);
extern CGError SLSGetCurrentCursorLocation(int cid, CGPoint *point);

extern uint64 SLSGetActiveSpace(int cid);
extern uint64 SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef screen);
extern CFArrayRef SLWindowListCreate(int cid);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);
extern CFArrayRef SLSCopySpacesForWindows(int cid, int mask, CFArrayRef windowIDs);

static bool IsValidWindow(CFTypeRef iterator) {
    uint64_t tags = SLSWindowIteratorGetTags(iterator);
    uint64_t attributes = SLSWindowIteratorGetAttributes(iterator);
    uint32_t parent_wid = SLSWindowIteratorGetParentID(iterator);
    if (((parent_wid == 0)
        && ((attributes & 0x2)
        || (tags & 0x400000000000000))
        && (((tags & 0x1))
        || ((tags & 0x2)
        && (tags & 0x80000000))))) {
        return true;
    }
    return false;
}

static bool IsValidDecorWindow(CFTypeRef iterator) { 
    uint32_t parent_wid = SLSWindowIteratorGetParentID(iterator);
    if (parent_wid == 0) {
        return true;
    }
    return false;
}

extern
int gConnection;

extern
int gWindowShift;

NSArray<NSDictionary *> *FilteredWindowList(unsigned long long current_space) {
    NSMutableArray<NSDictionary *> *tileableWindows = [NSMutableArray array];
    uint64_t set_tags = 1;     // Example tag condition
    uint64_t clear_tags = 0;   // Example tag condition

    // Create CFArray for the target space ID
    CFArrayRef space_list_ref = CFNumberArrayMake(&current_space,
                                                   sizeof(uint64_t),
                                                   1,
                                                   kCFNumberSInt64Type);
    if (!space_list_ref) {
        NSLog(@"Error: Failed to create space list CFArrayRef");
        return @[]; // Return empty array on failure
    }

    // Get window list for the specified space and tags
    CFArrayRef window_list = SLSCopyWindowsWithOptionsAndTags(gConnection,
                                                                0, // 0 = All windows owned by connection (effectively system-wide with appropriate connection)
                                                                space_list_ref,
                                                                0x2, // Options (e.g., kCGWindowListOptionOnScreenOnly, but using SPI raw value)
                                                                &set_tags,
                                                                &clear_tags);
    CFRelease(space_list_ref); // Release space list array

    // NSLog(@"Raw Window List: %@", window_list); // Debugging

    if (window_list) {
        uint32_t window_count = CFArrayGetCount(window_list);
        if (window_count > 0) {
            // Query details for the windows in the list
            CFTypeRef query = SLSWindowQueryWindows(gConnection, window_list, window_count); // Pass correct count
            if (query) {
                // Get an iterator for the query results
                CFTypeRef iterator = SLSWindowQueryResultCopyWindows(query);
                if (iterator) {
                    // Iterate through the windows
                    while(SLSWindowIteratorAdvance(iterator)) {
                        // Check if the window is one we want to manage/tile
                        if (IsValidWindow(iterator)) {
                            uint32_t wid = SLSWindowIteratorGetWindowID(iterator);
                            int wid_cid = 0; // Connection ID of the window's owner
                            pid_t pid = 0;   // Process ID of the window's owner

                            // Get the owner connection ID for the window
                            if (SLSGetWindowOwner(gConnection, wid, &wid_cid) == kCGErrorSuccess) {
                                // Get the PID from the owner connection ID
                                SLSConnectionGetPID(wid_cid, &pid);

                                NSDictionary *tileInfo = @{
                                    @"pid": @(pid), // Store PID
                                    @"wid": @(wid)  // Store Window ID
                                };
                                [tileableWindows addObject:tileInfo];
                            } else {
                                NSLog(@"Warning: Failed to get owner for WID %u", wid);
                            }
                        }
                    }
                    CFRelease(iterator); // Release iterator
                }
                CFRelease(query); // Release query object
            }
        }
        CFRelease(window_list); // Release original window list
    }
 
    NSSortDescriptor *sortByWID = [NSSortDescriptor sortDescriptorWithKey:@"wid" ascending:YES];
    NSArray<NSDictionary *> *sortedArray = [tileableWindows sortedArrayUsingDescriptors:@[sortByWID]];
 
    NSUInteger count = [sortedArray count]; 
    if (count == 0 || gWindowShift == 0) {
        return sortedArray;
    } 
    NSInteger effectiveShift = (gWindowShift % (NSInteger)count + (NSInteger)count) % (NSInteger)count; 
    if (effectiveShift == 0) {
        return sortedArray;
    } 

    NSMutableArray<NSDictionary *> *shiftedArray = [NSMutableArray arrayWithCapacity:count];
 
    for (NSUInteger newIndex = 0; newIndex < count; ++newIndex) { 
        NSInteger oldIndex = ((NSInteger)newIndex - effectiveShift + (NSInteger)count) % (NSInteger)count; 
        [shiftedArray addObject:[sortedArray objectAtIndex:(NSUInteger)oldIndex]];
    }
 
    return [shiftedArray copy];
}

NSArray<NSDictionary *> *SemiFilteredWindowList(unsigned long long current_space) {
    NSMutableArray<NSDictionary *> *tileableWindows = [NSMutableArray array];
    uint64_t set_tags = 1;     // Example tag condition
    uint64_t clear_tags = 0;   // Example tag condition

    // Create CFArray for the target space ID
    CFArrayRef space_list_ref = CFNumberArrayMake(&current_space,
                                                   sizeof(uint64_t),
                                                   1,
                                                   kCFNumberSInt64Type);
    if (!space_list_ref) {
        NSLog(@"Error: Failed to create space list CFArrayRef");
        return @[]; // Return empty array on failure
    }

    // Get window list for the specified space and tags
    CFArrayRef window_list = SLSCopyWindowsWithOptionsAndTags(gConnection,
                                                                0, // 0 = All windows owned by connection (effectively system-wide with appropriate connection)
                                                                space_list_ref,
                                                                0x2, // Options (e.g., kCGWindowListOptionOnScreenOnly, but using SPI raw value)
                                                                &set_tags,
                                                                &clear_tags);
    CFRelease(space_list_ref); // Release space list array

    // NSLog(@"Raw Window List: %@", window_list); // Debugging

    if (window_list) {
        uint32_t window_count = CFArrayGetCount(window_list);
        if (window_count > 0) {
            // Query details for the windows in the list
            CFTypeRef query = SLSWindowQueryWindows(gConnection, window_list, window_count); // Pass correct count
            if (query) {
                // Get an iterator for the query results
                CFTypeRef iterator = SLSWindowQueryResultCopyWindows(query);
                if (iterator) {
                    // Iterate through the windows
                    while(SLSWindowIteratorAdvance(iterator)) {
                        if (IsValidDecorWindow(iterator)) {
                            uint32_t wid = SLSWindowIteratorGetWindowID(iterator);
                            int wid_cid = 0; // Connection ID of the window's owner
                            pid_t pid = 0;   // Process ID of the window's owner

                            // Get the owner connection ID for the window
                            if (SLSGetWindowOwner(gConnection, wid, &wid_cid) == kCGErrorSuccess) {
                                // Get the PID from the owner connection ID
                                SLSConnectionGetPID(wid_cid, &pid);

                                NSDictionary *tileInfo = @{
                                    @"pid": @(pid), // Store PID
                                    @"wid": @(wid)  // Store Window ID
                                };
                                [tileableWindows addObject:tileInfo];
                            } else {
                                NSLog(@"Warning: Failed to get owner for WID %u", wid);
                            
                            }
                        }
                    }
                    CFRelease(iterator); // Release iterator
                }
                CFRelease(query); // Release query object
            }
        }
        CFRelease(window_list); // Release original window list
    }
 
    NSSortDescriptor *sortByWID = [NSSortDescriptor sortDescriptorWithKey:@"wid" ascending:YES];
    NSArray<NSDictionary *> *sortedArray = [tileableWindows sortedArrayUsingDescriptors:@[sortByWID]];
 
    NSUInteger count = [sortedArray count]; 
    if (count == 0 || gWindowShift == 0) {
        return sortedArray;
    } 
    NSInteger effectiveShift = (gWindowShift % (NSInteger)count + (NSInteger)count) % (NSInteger)count; 
    if (effectiveShift == 0) {
        return sortedArray;
    } 

    NSMutableArray<NSDictionary *> *shiftedArray = [NSMutableArray arrayWithCapacity:count];
 
    for (NSUInteger newIndex = 0; newIndex < count; ++newIndex) { 
        NSInteger oldIndex = ((NSInteger)newIndex - effectiveShift + (NSInteger)count) % (NSInteger)count; 
        [shiftedArray addObject:[sortedArray objectAtIndex:(NSUInteger)oldIndex]];
    }
 
    return [shiftedArray copy];
}