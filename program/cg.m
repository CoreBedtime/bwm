#include <ColorSync/ColorSync.h> /// ??? what
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

extern
int gConnection;

NSArray<NSDictionary *> *FilteredWindowList(void) {
    NSMutableArray *tileableWindows = [NSMutableArray array];
    uint64_t set_tags = 1;
    uint64_t clear_tags = 0;

    uint64_t sid = SLSGetActiveSpace(gConnection);

    CFArrayRef space_list_ref = CFNumberArrayMake(&sid,
                                                   sizeof(uint64_t),
                                                   1,
                                                   kCFNumberSInt64Type);

    CFArrayRef window_list = SLSCopyWindowsWithOptionsAndTags(gConnection,
                                                                0,
                                                                space_list_ref,
                                                                0x2,
                                                                &set_tags,
                                                                &clear_tags    );

    NSLog(@"%@", window_list);

    if (window_list) {
        uint32_t window_count = CFArrayGetCount(window_list);
        if (window_count > 0) {
            CFTypeRef query = SLSWindowQueryWindows(gConnection, window_list, 0x0);
            if (query) {
                CFTypeRef iterator = SLSWindowQueryResultCopyWindows(query);
                if (iterator) {
                    while(SLSWindowIteratorAdvance(iterator)) {
                        if (IsValidWindow(iterator)) {
                            uint32_t wid = SLSWindowIteratorGetWindowID(iterator);
                            int wid_cid = 0;
                            SLSGetWindowOwner(gConnection, wid, &wid_cid);

                            pid_t pid = 0;
                            SLSConnectionGetPID(wid_cid, &pid);

                            NSLog(@"%i", wid);
                            NSDictionary *tileInfo = @{
                                @"pid": @(pid),
                                @"wid": @(wid)
                            };
                            [tileableWindows addObject:tileInfo];
                            
                        }
                    }
                    CFRelease(iterator);
                    CFRelease(query);
                }
            }
            CFRelease(window_list);
        }
    }
    CFRelease(space_list_ref);

    // Sort by window ID
    NSSortDescriptor *sortByWID = [NSSortDescriptor sortDescriptorWithKey:@"wid" ascending:YES];
    return [tileableWindows sortedArrayUsingDescriptors:@[sortByWID]];\
}
