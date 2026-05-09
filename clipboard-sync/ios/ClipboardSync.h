#import <Foundation/Foundation.h>

@interface ClipboardSync : NSObject

@property (nonatomic, assign) BOOL isSettingFromNetwork;

+ (instancetype)sharedInstance;
- (void)start;
- (void)stop;
- (void)sendClipboard:(NSString *)text;

@end
