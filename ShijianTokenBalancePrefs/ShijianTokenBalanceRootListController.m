#import "ShijianTokenBalanceRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <roothide.h>
#import <notify.h>
#import <sys/stat.h>

static NSString *const ShijianTokenBalancePrefsPath = @"/var/mobile/Library/Preferences/com.shijian.tokenbalance.plist";
static const char *ShijianTokenBalanceChangedNotification = "com.shijian.tokenbalance/changed";

static NSString *ShijianTokenBalanceResolvedPrefsPath(void) {
    return jbroot(ShijianTokenBalancePrefsPath);
}

@implementation ShijianTokenBalanceRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:ShijianTokenBalanceResolvedPrefsPath()];
    return preferences[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    if ([key isEqualToString:@"windowScale"] && [value respondsToSelector:@selector(doubleValue)]) {
        value = @(MIN(1.50, MAX(0.75, [value doubleValue])));
    }

    NSString *path = ShijianTokenBalanceResolvedPrefsPath();
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableDictionary *preferences = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    if (value) preferences[key] = value;
    else [preferences removeObjectForKey:key];

    NSString *directory = [path stringByDeletingLastPathComponent];
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&directoryError];
    BOOL saved = !directoryError && [preferences writeToFile:path atomically:YES];
    if (saved) chmod(path.fileSystemRepresentation, 0600);

    if (!saved) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存" message:@"无法写入插件配置文件，请检查 RootHide 环境。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
        return;
    }

    notify_post(ShijianTokenBalanceChangedNotification);
}

@end
