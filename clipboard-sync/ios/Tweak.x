#import <UIKit/UIKit.h>
#import "ClipboardSync.h"

%hook UIPasteboard

- (void)setString:(NSString *)string {
    %orig;
    ClipboardSync *sync = [%c(ClipboardSync) sharedInstance];
    if (!sync.isSettingFromNetwork && [self isEqual:[UIPasteboard generalPasteboard]]) {
        [sync sendClipboard:string];
    }
}

%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [(ClipboardSync *)[%c(ClipboardSync) sharedInstance] start];
    });
}
