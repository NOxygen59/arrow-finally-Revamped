// Réglages › Arrow, Finally. Revamped: one switch or slider per thing the cursor
// does. Values go to the com.andyching.ipadarrowcursor domain; each change posts
// com.andyching.ipadarrowcursor/reload, and pointeruid applies it at once.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

static NSString *const ARRDomain = @"com.andyching.ipadarrowcursor";

@interface ARRRootListController : PSListController
@end

@implementation ARRRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

/// Every setting back to its default (the cursor as installed).
- (void)resetSettings {
    for (NSString *key in @[@"enabled", @"size", @"shadow", @"shakeToLocate", @"hideWhileTyping", @"uprightBeam"]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)ARRDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)ARRDomain);
    notify_post("com.andyching.ipadarrowcursor/reload");
    [self reloadSpecifiers];
}

/// Accessibility › Pointer Control, where iPadOS's own pointer size and auto-hide are.
- (void)openPointerControl {
    NSURL *url = [NSURL URLWithString:@"prefs:root=ACCESSIBILITY&path=POINTER_CONTROL_TITLE"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end
