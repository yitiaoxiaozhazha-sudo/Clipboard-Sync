#import "CSRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

static NSString * const kBundleID = @"com.yourcompany.clipboardsync";

@implementation CSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Clipboard Sync";
}

- (NSString *)preferencesPath {
    NSString *rootlessPath = [@"/var/jb/var/mobile/Library/Preferences"
                              stringByAppendingPathComponent:
                              [kBundleID stringByAppendingString:@".plist"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return rootlessPath;
    }
    return [@"/var/mobile/Library/Preferences"
            stringByAppendingPathComponent:
            [kBundleID stringByAppendingString:@".plist"]];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[self preferencesPath]];
    id value = settings[specifier.properties[@"key"]];
    return value ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = [self preferencesPath];
    NSMutableDictionary *settings = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy]
                                     ?: [NSMutableDictionary dictionary];
    settings[specifier.properties[@"key"]] = value;
    [settings writeToFile:path atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.yourcompany.clipboardsync-reload"),
        NULL, NULL, YES
    );
}

@end
