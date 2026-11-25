// A controller for the simulator tests: Apple's virtual controller, pressed by Darwin notifications the tests post.
// Inserted into the app with DYLD_INSERT_LIBRARIES by OortTrialTests, never shipped.
#import <UIKit/UIKit.h>
@import GameController;

static GCVirtualController *g_pad;

static NSString *element(NSString *name) {
    return @{@"a": GCInputButtonA, @"b": GCInputButtonB, @"x": GCInputButtonX, @"y": GCInputButtonY,
             @"l": GCInputLeftShoulder, @"r": GCInputRightShoulder, @"plus": GCInputButtonMenu}[name];
}

static void set(NSString *name, BOOL down) {
    NSString *button = element(name);
    if (button) { [g_pad setValue:down ? 1 : 0 forButtonElement:button]; return; }
    NSDictionary<NSString *, NSValue *> *ways = @{@"up": @(CGPointMake(0, 1)), @"down": @(CGPointMake(0, -1)),
                                                  @"left": @(CGPointMake(-1, 0)), @"right": @(CGPointMake(1, 0))};
    if (ways[name]) [g_pad setPosition:down ? ways[name].CGPointValue : CGPointZero forDirectionPadElement:GCInputDirectionPad];
}

static void heard(CFNotificationCenterRef c, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
    NSString *command = [(__bridge NSString *)name substringFromIndex:@"oort.pad.".length];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"oort pad: %@", command);
        if ([command isEqualToString:@"connect"]) {
            GCVirtualControllerConfiguration *configuration = [GCVirtualControllerConfiguration new];
            configuration.elements = [NSSet setWithArray:@[GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                                                           GCInputLeftShoulder, GCInputRightShoulder, GCInputDirectionPad, GCInputButtonMenu]];
            // Not drawn: the screen stays the app's.
            configuration.hidden = YES;
            g_pad = [GCVirtualController virtualControllerWithConfiguration:configuration];
            [g_pad connectWithReplyHandler:^(NSError *error) { NSLog(@"oort pad: %@", error ?: (id)@"connected"); }];
            return;
        }
        if ([command isEqualToString:@"disconnect"]) { [g_pad disconnect]; return; }
        NSArray<NSString *> *parts = [command componentsSeparatedByString:@"."];
        if (parts.count != 2) return;
        if ([parts[0] isEqualToString:@"hold"]) set(parts[1], YES);
        else if ([parts[0] isEqualToString:@"release"]) set(parts[1], NO);
        else {
            set(parts[1], YES);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.09 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ set(parts[1], NO); });
        }
    });
}

__attribute__((constructor)) static void listen(void) {
    NSMutableArray *names = [@[@"connect", @"disconnect"] mutableCopy];
    for (NSString *how in @[@"press", @"hold", @"release"])
        for (NSString *what in @[@"a", @"b", @"x", @"y", @"l", @"r", @"plus", @"up", @"down", @"left", @"right"])
            [names addObject:[NSString stringWithFormat:@"%@.%@", how, what]];
    for (NSString *one in names)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, heard,
                                        (__bridge CFStringRef)[@"oort.pad." stringByAppendingString:one], NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
}
