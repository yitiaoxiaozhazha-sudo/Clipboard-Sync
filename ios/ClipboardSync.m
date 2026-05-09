#import "ClipboardSync.h"
#import <UIKit/UIKit.h>

static NSString * const kPreferencesIdentifier = @"com.yourcompany.clipboardsync";

@interface ClipboardSync () <NSStreamDelegate>
@property (nonatomic, strong) NSThread *networkThread;
@property (nonatomic, assign) BOOL shouldReconnect;
@property (nonatomic, strong) NSMutableString *receiveBuffer;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, copy) NSString *pendingMessage;
@end

@implementation ClipboardSync

+ (instancetype)sharedInstance {
    static ClipboardSync *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ClipboardSync alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _shouldReconnect = YES;
        _receiveBuffer = [NSMutableString string];
    }
    return self;
}

#pragma mark - Preferences

- (NSString *)preferencesFilePath {
    NSString *rootlessPath = @"/var/jb/var/mobile/Library/Preferences/com.yourcompany.clipboardsync.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return rootlessPath;
    }
    return @"/var/mobile/Library/Preferences/com.yourcompany.clipboardsync.plist";
}

- (NSDictionary *)loadPreferences {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[self preferencesFilePath]];
    return prefs ?: @{};
}

- (BOOL)isEnabled {
    NSDictionary *prefs = [self loadPreferences];
    id enabled = prefs[@"enabled"];
    if (enabled == nil) return YES;
    return [enabled boolValue];
}

- (NSString *)host {
    NSDictionary *prefs = [self loadPreferences];
    NSString *host = prefs[@"ip"];
    return host.length > 0 ? host : @"192.168.1.100";
}

- (NSInteger)port {
    NSDictionary *prefs = [self loadPreferences];
    id portVal = prefs[@"port"];
    if (portVal) {
        if ([portVal isKindOfClass:[NSString class]]) {
            return [(NSString *)portVal integerValue];
        }
        if ([portVal isKindOfClass:[NSNumber class]]) {
            return [portVal integerValue];
        }
    }
    return 9527;
}

- (void)reloadPreferences {
    [self disconnect];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([self isEnabled]) {
            [self performSelector:@selector(connect) onThread:self.networkThread withObject:nil waitUntilDone:NO];
        }
    });
}

#pragma mark - Public Methods

- (void)start {
    if (![self isEnabled]) {
        NSLog(@"[ClipboardSync] Disabled");
        return;
    }

    self.shouldReconnect = YES;
    if (self.networkThread && self.networkThread.isExecuting) return;

    self.networkThread = [[NSThread alloc] initWithTarget:self
                                                 selector:@selector(networkThreadMain)
                                                   object:nil];
    self.networkThread.name = @"ClipboardSync.Network";
    [self.networkThread start];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        preferencesChangedCallback,
        CFSTR("com.yourcompany.clipboardsync-reload"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

- (void)stop {
    self.shouldReconnect = NO;
    [self disconnect];
    [self.networkThread cancel];
    self.networkThread = nil;

    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CFSTR("com.yourcompany.clipboardsync-reload"),
        NULL
    );
}

#pragma mark - Callback

static void preferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ClipboardSync *sync = (__bridge ClipboardSync *)observer;
    [sync reloadPreferences];
}

#pragma mark - Network Thread

- (void)networkThreadMain {
    @autoreleasepool {
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [self connect];

        NSTimer *pingTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                              target:self
                                                            selector:@selector(sendPing)
                                                            userInfo:nil
                                                             repeats:YES];
        [runLoop addTimer:pingTimer forMode:NSDefaultRunLoopMode];

        while (self.shouldReconnect && ![NSThread currentThread].isCancelled) {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }

        [pingTimer invalidate];
        [self disconnect];
    }
}

- (void)connect {
    [self disconnect];

    NSString *host = [self host];
    NSInteger port = [self port];

    NSLog(@"[ClipboardSync] Connecting to %@:%ld", host, (long)port);

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host,
                                       (uint32_t)port, &readStream, &writeStream);

    if (!readStream || !writeStream) {
        NSLog(@"[ClipboardSync] Failed to create streams");
        [self scheduleReconnect];
        return;
    }

    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;

    [self.inputStream setDelegate:self];
    [self.outputStream setDelegate:self];

    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                 forMode:NSDefaultRunLoopMode];

    [self.inputStream open];
    [self.outputStream open];
}

- (void)disconnect {
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                    forMode:NSDefaultRunLoopMode];
        self.inputStream = nil;
    }
    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                    forMode:NSDefaultRunLoopMode];
        self.outputStream = nil;
    }
    self.connected = NO;
}

- (void)scheduleReconnect {
    if (!self.shouldReconnect) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self performSelector:@selector(connect)
                     onThread:self.networkThread
                   withObject:nil
                waitUntilDone:NO];
    });
}

#pragma mark - Sending

- (void)sendClipboard:(NSString *)text {
    if (!self.connected || !text || text.length == 0) return;

    NSDictionary *msg = @{@"cmd": @"set", @"text": text};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    if (!jsonData) return;

    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    self.pendingMessage = [jsonStr stringByAppendingString:@"\n"];
    [self flushOutput];
}

- (void)sendPing {
    if (!self.connected) return;
    self.pendingMessage = @"{\"cmd\":\"ping\"}\n";
    [self flushOutput];
}

- (void)flushOutput {
    if (!self.pendingMessage || !self.outputStream) return;
    if (![self.outputStream hasSpaceAvailable]) return;

    NSData *data = [self.pendingMessage dataUsingEncoding:NSUTF8StringEncoding];
    NSInteger written = [self.outputStream write:data.bytes maxLength:data.length];
    if (written > 0) {
        self.pendingMessage = nil;
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"[ClipboardSync] Stream opened");
            if (aStream == self.outputStream) {
                self.connected = YES;
            }
            break;

        case NSStreamEventHasBytesAvailable:
            [self handleIncomingData];
            break;

        case NSStreamEventHasSpaceAvailable:
            [self flushOutput];
            break;

        case NSStreamEventErrorOccurred:
            NSLog(@"[ClipboardSync] Stream error: %@", aStream.streamError);
        case NSStreamEventEndEncountered:
            NSLog(@"[ClipboardSync] Connection closed");
            [self disconnect];
            [self scheduleReconnect];
            break;

        default:
            break;
    }
}

- (void)handleIncomingData {
    uint8_t buffer[4096];
    NSInteger bytesRead = [self.inputStream read:buffer maxLength:sizeof(buffer)];

    if (bytesRead <= 0) return;

    NSString *data = [[NSString alloc] initWithBytes:buffer
                                              length:bytesRead
                                            encoding:NSUTF8StringEncoding];
    if (!data) return;

    [self.receiveBuffer appendString:data];

    while (YES) {
        NSRange newlineRange = [self.receiveBuffer rangeOfString:@"\n"];
        if (newlineRange.location == NSNotFound) break;

        NSString *line = [self.receiveBuffer substringToIndex:newlineRange.location];
        [self.receiveBuffer deleteCharactersInRange:NSMakeRange(0, newlineRange.location + 1)];

        [self processMessage:line];
    }
}

- (void)processMessage:(NSString *)line {
    if (line.length == 0) return;

    NSData *jsonData = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!msg) return;

    NSString *cmd = msg[@"cmd"];

    if ([cmd isEqualToString:@"set"]) {
        NSString *text = msg[@"text"];
        if (text) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isSettingFromNetwork = YES;
                [[UIPasteboard generalPasteboard] setString:text];
                self.isSettingFromNetwork = NO;
            });
        }
    }
    // pong is silently handled for keep-alive
}

@end
