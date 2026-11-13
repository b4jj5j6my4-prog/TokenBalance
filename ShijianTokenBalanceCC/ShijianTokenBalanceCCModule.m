#import "CCUIToggleModule.h"
#import <roothide.h>
#import <notify.h>
#import <sys/stat.h>

static NSString *const ShijianTokenBalanceCCPrefsPath = @"/var/mobile/Library/Preferences/com.shijian.tokenbalance.plist";
static const char *ShijianTokenBalanceCCChangedNotification = "com.shijian.tokenbalance/changed";

@interface ShijianTokenBalanceCCModule : CCUIToggleModule
@property(nonatomic, assign) int preferencesNotificationToken;
@end

@implementation ShijianTokenBalanceCCModule

- (instancetype)init {
    self = [super init];
    if (self) {
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch(ShijianTokenBalanceCCChangedNotification, &_preferencesNotificationToken, dispatch_get_main_queue(), ^(__unused int token) {
            [weakSelf refreshState];
        });
    }
    return self;
}

- (void)dealloc {
    if (_preferencesNotificationToken > 0) notify_cancel(_preferencesNotificationToken);
}

- (NSString *)shijianTokenBalanceResolvedPrefsPath {
    return jbroot(ShijianTokenBalanceCCPrefsPath);
}

- (BOOL)isSelected {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:[self shijianTokenBalanceResolvedPrefsPath]];
    id value = preferences[@"enabled"];
    return value ? [value boolValue] : YES;
}

- (void)setSelected:(BOOL)selected {
    NSString *path = [self shijianTokenBalanceResolvedPrefsPath];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableDictionary *preferences = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    preferences[@"enabled"] = @(selected);
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    if ([preferences writeToFile:path atomically:YES]) chmod(path.fileSystemRepresentation, 0600);
    notify_post(ShijianTokenBalanceCCChangedNotification);
    [super setSelected:selected];
}

- (UIImage *)iconGlyph {
    if (@available(iOS 13.0, *)) return [UIImage systemImageNamed:@"dollarsign.circle"];
    return nil;
}

- (UIColor *)selectedColor {
    return [UIColor colorWithWhite:0.18 alpha:1.0];
}

@end
