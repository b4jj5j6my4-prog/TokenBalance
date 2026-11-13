#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <os/log.h>
#import <roothide.h>
#import <notify.h>
#import <sys/stat.h>

static NSString *const ShijianTokenBalanceConfigFile = @"/var/mobile/Library/Preferences/com.shijian.tokenbalance.plist";
static const char *ShijianTokenBalanceChangedNotification = "com.shijian.tokenbalance/changed";

static os_log_t ShijianTokenBalanceLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.shijian.tokenbalance", "runtime");
    });
    return log;
}

static NSString *ShijianTokenBalanceConfigPath(void) {
    return jbroot(ShijianTokenBalanceConfigFile);
}

static id ShijianTokenBalanceValueAtPath(id object, NSString *path) {
    if (!object || path.length == 0) return nil;
    id value = object;
    for (NSString *component in [path componentsSeparatedByString:@"."]) {
        if ([value isKindOfClass:NSDictionary.class]) {
            value = [(NSDictionary *)value objectForKey:component];
        } else if ([value isKindOfClass:NSArray.class]) {
            NSScanner *scanner = [NSScanner scannerWithString:component];
            NSInteger index = 0;
            if (![scanner scanInteger:&index] || !scanner.isAtEnd || index < 0 || index >= (NSInteger)[(NSArray *)value count]) return nil;
            value = [(NSArray *)value objectAtIndex:(NSUInteger)index];
        } else {
            return nil;
        }
        if (!value || value == NSNull.null) return nil;
    }
    return value;
}

static NSNumber *ShijianTokenBalanceNumber(id value) {
    if (![value respondsToSelector:@selector(doubleValue)] || [value isKindOfClass:NSNull.class]) return nil;
    return @([value doubleValue]);
}

static void ShijianTokenBalanceSetNumber(NSMutableDictionary *result, NSString *key, id value) {
    NSNumber *number = ShijianTokenBalanceNumber(value);
    if (number) result[key] = number;
}

static NSDictionary *ShijianTokenBalanceParsedResult(id json, NSDictionary *config) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *object = (NSDictionary *)json;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    if ([object[@"isValid"] isKindOfClass:NSNumber.class]) {
        if (![object[@"isValid"] boolValue]) result[@"rejected"] = @YES;
        NSString *mode = [object[@"mode"] isKindOfClass:NSString.class] ? object[@"mode"] : @"";
        NSDictionary *usage = [object[@"usage"] isKindOfClass:NSDictionary.class] ? object[@"usage"] : nil;
        NSDictionary *usageTotal = [usage[@"total"] isKindOfClass:NSDictionary.class] ? usage[@"total"] : nil;
        NSNumber *actualCost = ShijianTokenBalanceNumber(usageTotal[@"actual_cost"]);
        if ([mode isEqualToString:@"quota_limited"]) {
            NSDictionary *quota = [object[@"quota"] isKindOfClass:NSDictionary.class] ? object[@"quota"] : @{};
            ShijianTokenBalanceSetNumber(result, @"available", quota[@"remaining"]);
            ShijianTokenBalanceSetNumber(result, @"total", quota[@"limit"]);
            ShijianTokenBalanceSetNumber(result, @"used", quota[@"used"]);
            if (!result[@"used"] && actualCost) result[@"used"] = actualCost;
            result[@"label"] = @"密钥额度";
        } else if (object[@"balance"] && object[@"balance"] != NSNull.null) {
            ShijianTokenBalanceSetNumber(result, @"available", object[@"balance"]);
            if (actualCost) result[@"used"] = actualCost;
            result[@"label"] = @"钱包余额";
        } else {
            NSNumber *remaining = ShijianTokenBalanceNumber(object[@"remaining"]);
            if (remaining.doubleValue < 0) result[@"unlimited"] = @YES;
            else if (remaining) result[@"available"] = remaining;
            if (actualCost) result[@"used"] = actualCost;
            result[@"label"] = @"订阅额度";
        }
        result[@"unit"] = @"USD";
        return result;
    }

    NSDictionary *data = [object[@"data"] isKindOfClass:NSDictionary.class] ? object[@"data"] : nil;
    if (data && (data[@"total_granted"] || data[@"total_available"])) {
        NSNumber *granted = ShijianTokenBalanceNumber(data[@"total_granted"]);
        BOOL unlimited = [data[@"unlimited_quota"] boolValue] || granted.doubleValue < 0;
        ShijianTokenBalanceSetNumber(result, @"total", granted);
        ShijianTokenBalanceSetNumber(result, @"used", data[@"total_used"]);
        ShijianTokenBalanceSetNumber(result, @"available", data[@"total_available"]);
        result[@"unlimited"] = @(unlimited);
        result[@"label"] = @"账户额度";
        return result;
    }

    if (data && (data[@"quota"] || data[@"used_quota"])) {
        double total = [data[@"quota"] doubleValue] / 500000.0;
        double used = [data[@"used_quota"] doubleValue] / 500000.0;
        result[@"total"] = @(total);
        result[@"used"] = @(used);
        result[@"available"] = @(MAX(0, total - used));
        result[@"label"] = @"账户额度";
        result[@"unit"] = @"USD";
        return result;
    }

    NSDictionary *billing = data ?: object;
    NSNumber *balance = ShijianTokenBalanceNumber(billing[@"balance"]);
    NSNumber *hardLimit = ShijianTokenBalanceNumber(billing[@"hard_limit_usd"]);
    if (balance || hardLimit) {
        if (balance) result[@"available"] = balance;
        if (hardLimit) {
            result[@"total"] = hardLimit;
            result[@"unlimited"] = @(hardLimit.doubleValue >= 100000000.0);
        }
        ShijianTokenBalanceSetNumber(result, @"used", billing[@"total_used"] ?: billing[@"used"]);
        result[@"label"] = balance ? @"账户余额" : @"消费限额";
        result[@"unit"] = @"USD";
        return result;
    }

    NSNumber *available = ShijianTokenBalanceNumber(ShijianTokenBalanceValueAtPath(json, config[@"availablePath"]));
    if (!available) return nil;
    result[@"available"] = available;
    ShijianTokenBalanceSetNumber(result, @"total", ShijianTokenBalanceValueAtPath(json, config[@"totalPath"]));
    ShijianTokenBalanceSetNumber(result, @"used", ShijianTokenBalanceValueAtPath(json, config[@"usedPath"]));
    result[@"label"] = @"账户余额";
    return result;
}

@interface ShijianTokenBalanceController : NSObject <UIGestureRecognizerDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIWindow *configWindow;
@property(nonatomic, strong) UIViewController *rootController;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *balanceLabel;
@property(nonatomic, strong) UILabel *compactBalanceLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSDictionary *config;
@property(nonatomic, assign) BOOL collapsed;
@property(nonatomic, assign) BOOL deviceLocked;
@property(nonatomic, assign) CGPoint panOrigin;
@property(nonatomic, assign) CGRect panStartFrame;
@property(nonatomic, assign) NSInteger resizeCorner;
@property(nonatomic, assign) int lockStateNotificationToken;
@property(nonatomic, assign) int lockCompleteNotificationToken;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) NSUInteger refreshGeneration;
@end

@implementation ShijianTokenBalanceController

+ (instancetype)sharedController {
    static ShijianTokenBalanceController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [ShijianTokenBalanceController new];
    });
    return controller;
}

- (NSDictionary *)defaultConfig {
    return @{
        @"enabled": @YES,
        @"locked": @NO,
        @"endpoint": @"",
        @"apiKey": @"",
        @"availablePath": @"total_available",
        @"totalPath": @"total_granted",
        @"usedPath": @"total_used",
        @"refreshInterval": @60,
        @"windowScale": @1.0,
        @"x": @16,
        @"y": @120
    };
}

- (void)loadConfig {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:ShijianTokenBalanceConfigPath()];
    NSMutableDictionary *merged = [[self defaultConfig] mutableCopy];
    if ([stored isKindOfClass:NSDictionary.class]) [merged addEntriesFromDictionary:stored];
    self.config = merged;
}

- (void)saveConfig:(NSDictionary *)config {
    NSString *path = ShijianTokenBalanceConfigPath();
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [config writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0600);
    self.config = config;
}

- (CGFloat)windowScale {
    return MIN(1.50, MAX(0.75, [self.config[@"windowScale"] doubleValue]));
}

- (void)applyWindowScale {
    if (!self.window) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat scale = [self windowScale];
    CGFloat width = 184 * scale;
    CGFloat expandedHeight = 88 * scale;
    CGFloat height = self.collapsed ? 40 * scale : expandedHeight;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGRect frame = self.window.frame;
    frame.size = CGSizeMake(width, height);
    frame.origin.x = MAX(8, MIN(frame.origin.x, CGRectGetWidth(screen) - width - 8));
    frame.origin.y = MAX(44, MIN(frame.origin.y, CGRectGetHeight(screen) - height - 8));
    self.window.frame = frame;
    self.rootController.view.frame = self.window.bounds;
    self.window.layer.cornerRadius = 10 * scale;

    self.titleLabel.frame = CGRectMake(12 * scale, 8 * scale, 132 * scale, 18 * scale);
    self.titleLabel.font = [UIFont systemFontOfSize:12 * scale weight:UIFontWeightMedium];
    self.balanceLabel.frame = CGRectMake(12 * scale, 28 * scale, 160 * scale, 28 * scale);
    self.balanceLabel.font = [UIFont monospacedDigitSystemFontOfSize:21 * scale weight:UIFontWeightSemibold];
    self.compactBalanceLabel.frame = CGRectMake(84 * scale, 8 * scale, 88 * scale, 18 * scale);
    self.compactBalanceLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 * scale weight:UIFontWeightSemibold];
    self.detailLabel.frame = CGRectMake(12 * scale, 62 * scale, 160 * scale, 16 * scale);
    self.detailLabel.font = [UIFont systemFontOfSize:11 * scale weight:UIFontWeightRegular];
    self.spinner.bounds = CGRectMake(0, 0, 28, 24);
    self.spinner.center = CGPointMake(162 * scale, 17 * scale);
    self.spinner.transform = CGAffineTransformMakeScale(0.72 * scale, 0.72 * scale);
    [CATransaction commit];
}

- (void)updateWindowVisibility {
    self.window.hidden = self.deviceLocked || ![self.config[@"enabled"] boolValue];
}

- (void)updateDeviceLockedFromToken:(int)token fallback:(BOOL)fallback {
    uint64_t state = 0;
    if (fallback) state = 1;
    else if (token > 0) notify_get_state(token, &state);
    self.deviceLocked = state != 0;
    [self updateWindowVisibility];
}

- (void)start {
    if (self.started) return;
    self.started = YES;
    [self loadConfig];

    UIWindowScene *windowScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
                windowScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (!windowScene) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:UIWindowScene.class]) {
                    windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
    }

    CGRect screen = windowScene ? windowScene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    CGFloat scale = [self windowScale];
    CGFloat windowWidth = 184 * scale;
    CGFloat windowHeight = 88 * scale;
    CGFloat x = [self.config[@"x"] doubleValue];
    CGFloat y = [self.config[@"y"] doubleValue];
    x = MAX(8, MIN(x, CGRectGetWidth(screen) - windowWidth - 8));
    y = MAX(44, MIN(y, CGRectGetHeight(screen) - windowHeight - 8));

    if (@available(iOS 13.0, *)) {
        self.window = windowScene ? [[UIWindow alloc] initWithWindowScene:windowScene] : [[UIWindow alloc] initWithFrame:CGRectMake(x, y, windowWidth, windowHeight)];
        self.window.frame = CGRectMake(x, y, windowWidth, windowHeight);
    } else {
        self.window = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, windowWidth, windowHeight)];
    }
    self.window.windowLevel = UIWindowLevelAlert + 2;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.layer.cornerRadius = 10;
    self.window.clipsToBounds = YES;

    self.rootController = [UIViewController new];
    self.rootController.view.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.92];
    self.window.rootViewController = self.rootController;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 132, 18)];
    self.titleLabel.text = @"API 账户余额";
    self.titleLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    self.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

    self.balanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 28, 160, 28)];
    self.balanceLabel.text = @"长按配置";
    self.balanceLabel.textColor = UIColor.whiteColor;
    self.balanceLabel.font = [UIFont monospacedDigitSystemFontOfSize:21 weight:UIFontWeightSemibold];
    self.balanceLabel.adjustsFontSizeToFitWidth = YES;
    self.balanceLabel.minimumScaleFactor = 0.72;

    self.compactBalanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(84, 8, 88, 18)];
    self.compactBalanceLabel.text = self.balanceLabel.text;
    self.compactBalanceLabel.textColor = UIColor.whiteColor;
    self.compactBalanceLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    self.compactBalanceLabel.textAlignment = NSTextAlignmentRight;
    self.compactBalanceLabel.adjustsFontSizeToFitWidth = YES;
    self.compactBalanceLabel.minimumScaleFactor = 0.72;
    self.compactBalanceLabel.hidden = YES;

    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 62, 160, 16)];
    self.detailLabel.text = @"尚未配置接口";
    self.detailLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    self.detailLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    self.detailLabel.adjustsFontSizeToFitWidth = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.frame = CGRectMake(148, 5, 28, 24);
    self.spinner.transform = CGAffineTransformMakeScale(0.72, 0.72);

    [self.rootController.view addSubview:self.titleLabel];
    [self.rootController.view addSubview:self.balanceLabel];
    [self.rootController.view addSubview:self.compactBalanceLabel];
    [self.rootController.view addSubview:self.detailLabel];
    [self.rootController.view addSubview:self.spinner];
    [self applyWindowScale];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    tap.delegate = self;
    [tap requireGestureRecognizerToFail:longPress];
    [self.rootController.view addGestureRecognizer:tap];
    [self.rootController.view addGestureRecognizer:longPress];
    [self.rootController.view addGestureRecognizer:pan];

    __weak typeof(self) weakSelf = self;
    notify_register_dispatch("com.apple.springboard.lockstate", &_lockStateNotificationToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf updateDeviceLockedFromToken:token fallback:NO];
    });
    notify_register_dispatch("com.apple.springboard.lockcomplete", &_lockCompleteNotificationToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf updateDeviceLockedFromToken:token fallback:YES];
    });
    [self updateDeviceLockedFromToken:self.lockStateNotificationToken fallback:NO];
    [self scheduleRefresh];
    if ([self.config[@"enabled"] boolValue]) [self refresh];

    int token = 0;
    notify_register_dispatch(ShijianTokenBalanceChangedNotification, &token, dispatch_get_main_queue(), ^(__unused int notificationToken) {
        [weakSelf applyChangedConfiguration];
    });
}

- (void)applyChangedConfiguration {
    [self loadConfig];
    BOOL enabled = [self.config[@"enabled"] boolValue];
    [self updateWindowVisibility];
    [self applyWindowScale];
    [self scheduleRefresh];
    if (enabled) [self refresh];
    else {
        [self.spinner stopAnimating];
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (void)scheduleRefresh {
    [self.timer invalidate];
    NSTimeInterval interval = MAX(15, [self.config[@"refreshInterval"] doubleValue]);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    NSURL *fromURL = task.currentRequest.URL;
    NSURL *toURL = request.URL;
    BOOL sameHost = [fromURL.host caseInsensitiveCompare:toURL.host] == NSOrderedSame;
    BOOL secure = [toURL.scheme.lowercaseString isEqualToString:@"https"];
    completionHandler(sameHost && secure ? request : nil);
}

- (NSArray<NSURL *> *)candidateURLsForEndpoint:(NSURL *)endpoint {
    NSString *path = endpoint.path ?: @"";
    if (path.length > 0 && ![path isEqualToString:@"/"]) return @[endpoint];
    NSURLComponents *base = [NSURLComponents componentsWithURL:endpoint resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *candidatePath in @[@"/v1/usage", @"/api/usage/token", @"/api/user/self", @"/dashboard/billing/credit_grants", @"/dashboard/billing/subscription"]) {
        NSURLComponents *components = [base copy];
        components.path = candidatePath;
        components.query = nil;
        components.fragment = nil;
        if (components.URL) [urls addObject:components.URL];
    }
    return urls;
}

- (void)setBalanceText:(NSString *)text {
    self.balanceLabel.text = text;
    self.compactBalanceLabel.text = text;
}

- (void)showParsedResult:(NSDictionary *)result {
    if ([result[@"rejected"] boolValue]) {
        [self setBalanceText:@"密钥无效"];
        self.detailLabel.text = @"接口已拒绝此 API Key";
        return;
    }
    NSString *label = result[@"label"] ?: @"账户余额";
    NSNumber *available = result[@"available"];
    NSNumber *total = result[@"total"];
    NSNumber *used = result[@"used"];
    BOOL unlimited = [result[@"unlimited"] boolValue];
    if (unlimited && !available) [self setBalanceText:[NSString stringWithFormat:@"%@ 不限量", label]];
    else if (available) [self setBalanceText:[NSString stringWithFormat:@"%@ %.2f", label, available.doubleValue]];
    else if (total) [self setBalanceText:[NSString stringWithFormat:@"%@ %.2f", label, total.doubleValue]];
    else [self setBalanceText:label];

    if (unlimited && used) self.detailLabel.text = [NSString stringWithFormat:@"不限量  已用 %.2f", used.doubleValue];
    else if (total && used) self.detailLabel.text = [NSString stringWithFormat:@"总额 %.2f  已用 %.2f", total.doubleValue, used.doubleValue];
    else if (total) self.detailLabel.text = [NSString stringWithFormat:@"总额 %.2f", total.doubleValue];
    else if (used) self.detailLabel.text = [NSString stringWithFormat:@"已用 %.2f", used.doubleValue];
    else self.detailLabel.text = @"账户额度已更新";
}

- (void)requestCandidates:(NSArray<NSURL *> *)candidates index:(NSUInteger)index apiKey:(NSString *)apiKey generation:(NSUInteger)generation lastStatus:(NSInteger)lastStatus {
    if (generation != self.refreshGeneration) return;
    if (index >= candidates.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.refreshGeneration) return;
            [self.spinner stopAnimating];
            [self setBalanceText:lastStatus == 401 || lastStatus == 403 ? @"认证失败" : @"无法识别"];
            self.detailLabel.text = lastStatus > 0 ? [NSString stringWithFormat:@"HTTP %ld 或响应格式不支持", (long)lastStatus] : @"未找到可用的余额协议";
        });
        return;
    }

    NSURL *url = candidates[index];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:apiKey forHTTPHeaderField:@"x-goog-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPShouldSetCookies = NO;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.refreshGeneration) return;
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (!error && statusCode >= 200 && statusCode < 300) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *result = ShijianTokenBalanceParsedResult(json, self.config);
            if (result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.refreshGeneration) return;
                    [self.spinner stopAnimating];
                    [self showParsedResult:result];
                });
                return;
            }
        }
        BOOL authenticationFailed = statusCode == 401 || statusCode == 403;
        BOOL isSingleEndpoint = candidates.count == 1;
        if (authenticationFailed && isSingleEndpoint) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.refreshGeneration) return;
                [self.spinner stopAnimating];
                [self setBalanceText:@"认证失败"];
                self.detailLabel.text = [NSString stringWithFormat:@"HTTP %ld，请检查 API Key", (long)statusCode];
            });
            return;
        }
        [self requestCandidates:candidates index:index + 1 apiKey:apiKey generation:generation lastStatus:statusCode ?: lastStatus];
    }] resume];
    [session finishTasksAndInvalidate];
}

- (void)refresh {
    NSString *endpointString = [self.config[@"endpoint"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *apiKey = [self.config[@"apiKey"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *endpoint = [NSURL URLWithString:endpointString ?: @""];
    if (!endpoint || ![endpoint.scheme.lowercaseString isEqualToString:@"https"] || endpoint.host.length == 0 || apiKey.length == 0) {
        [self setBalanceText:@"长按配置"];
        self.detailLabel.text = @"需要 HTTPS 地址与 API Key";
        return;
    }

    self.refreshGeneration += 1;
    [self.spinner startAnimating];
    [self requestCandidates:[self candidateURLsForEndpoint:endpoint] index:0 apiKey:apiKey generation:self.refreshGeneration lastStatus:0];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    self.collapsed = !self.collapsed;
    CGRect frame = self.window.frame;
    frame.size.height = (self.collapsed ? 40 : 88) * [self windowScale];
    [UIView animateWithDuration:0.2 animations:^{
        self.window.frame = frame;
        self.balanceLabel.alpha = self.collapsed ? 0 : 1;
        self.detailLabel.alpha = self.collapsed ? 0 : 1;
        self.compactBalanceLabel.hidden = !self.collapsed;
        self.compactBalanceLabel.alpha = self.collapsed ? 1 : 0;
    }];
}

- (NSInteger)resizeCornerAtPoint:(CGPoint)point {
    CGFloat inset = MIN(32.0, 28.0 * [self windowScale]);
    BOOL left = point.x <= inset;
    BOOL right = point.x >= CGRectGetWidth(self.window.bounds) - inset;
    BOOL top = point.y <= inset;
    BOOL bottom = point.y >= CGRectGetHeight(self.window.bounds) - inset;
    if (left && top) return 1;
    if (right && top) return 2;
    if (left && bottom) return 3;
    if (right && bottom) return 4;
    return 0;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if ([self.config[@"locked"] boolValue]) return;
    CGPoint translation = [gesture translationInView:self.window.superview];
    CGRect screen = UIScreen.mainScreen.bounds;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.panOrigin = self.window.frame.origin;
        self.panStartFrame = self.window.frame;
        self.resizeCorner = self.collapsed ? 0 : [self resizeCornerAtPoint:[gesture locationInView:self.window]];
    }

    CGRect frame = self.panStartFrame;
    if (self.resizeCorner != 0) {
        CGFloat directionX = (self.resizeCorner == 1 || self.resizeCorner == 3) ? -1.0 : 1.0;
        CGFloat directionY = (self.resizeCorner == 1 || self.resizeCorner == 2) ? -1.0 : 1.0;
        CGFloat projectedDelta = (translation.x * directionX * 184.0 + translation.y * directionY * 88.0) / (184.0 * 184.0 + 88.0 * 88.0);
        CGFloat startingScale = CGRectGetWidth(self.panStartFrame) / 184.0;
        CGFloat scale = MIN(1.50, MAX(0.75, startingScale + projectedDelta));
        CGFloat width = 184 * scale;
        CGFloat height = 88 * scale;
        CGFloat anchorX = (self.resizeCorner == 1 || self.resizeCorner == 3) ? CGRectGetMaxX(self.panStartFrame) : CGRectGetMinX(self.panStartFrame);
        CGFloat anchorY = (self.resizeCorner == 1 || self.resizeCorner == 2) ? CGRectGetMaxY(self.panStartFrame) : CGRectGetMinY(self.panStartFrame);
        frame.origin.x = (self.resizeCorner == 1 || self.resizeCorner == 3) ? anchorX - width : anchorX;
        frame.origin.y = (self.resizeCorner == 1 || self.resizeCorner == 2) ? anchorY - height : anchorY;
        frame.size = CGSizeMake(width, height);
        frame.origin.x = MAX(8, MIN(frame.origin.x, CGRectGetWidth(screen) - width - 8));
        frame.origin.y = MAX(44, MIN(frame.origin.y, CGRectGetHeight(screen) - height - 8));
        NSMutableDictionary *liveConfig = [self.config mutableCopy];
        liveConfig[@"windowScale"] = @(scale);
        liveConfig[@"x"] = @(frame.origin.x);
        liveConfig[@"y"] = @(frame.origin.y);
        self.config = liveConfig;
        self.window.frame = frame;
        [self applyWindowScale];
    } else {
        frame = self.window.frame;
        frame.origin.x = MAX(8, MIN(self.panOrigin.x + translation.x, CGRectGetWidth(screen) - CGRectGetWidth(frame) - 8));
        frame.origin.y = MAX(44, MIN(self.panOrigin.y + translation.y, CGRectGetHeight(screen) - CGRectGetHeight(frame) - 8));
        self.window.frame = frame;
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        NSMutableDictionary *config = [self.config mutableCopy];
        config[@"x"] = @(self.window.frame.origin.x);
        config[@"y"] = @(self.window.frame.origin.y);
        if (self.resizeCorner != 0) config[@"windowScale"] = @([self windowScale]);
        [self saveConfig:config];
        notify_post(ShijianTokenBalanceChangedNotification);
        self.resizeCorner = 0;
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self presentConfiguration];
}

- (void)presentConfiguration {
    self.configWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.configWindow.windowLevel = UIWindowLevelAlert + 10;
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    self.configWindow.rootViewController = controller;
    self.configWindow.hidden = NO;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Token 余额浮窗" message:@"填写 HTTPS 平台根地址可自动识别；填写完整接口则直接请求。浮窗缩放范围为 0.75–1.50。" preferredStyle:UIAlertControllerStyleAlert];
    NSArray<NSString *> *placeholders = @[@"平台根地址或完整接口 URL", @"API Key", @"剩余额度字段路径", @"总额度字段路径", @"已用额度字段路径", @"刷新秒数（最低 15）", @"浮窗缩放（0.75–1.50）"];
    NSArray *values = @[self.config[@"endpoint"] ?: @"", self.config[@"apiKey"] ?: @"", self.config[@"availablePath"] ?: @"", self.config[@"totalPath"] ?: @"", self.config[@"usedPath"] ?: @"", [self.config[@"refreshInterval"] stringValue] ?: @"60", [NSString stringWithFormat:@"%.2f", [self windowScale]]];
    for (NSUInteger index = 0; index < placeholders.count; index++) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = placeholders[index];
            field.text = values[index];
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            if (index == 0) field.keyboardType = UIKeyboardTypeURL;
            if (index == 1) field.secureTextEntry = YES;
            if (index == 5) field.keyboardType = UIKeyboardTypeNumberPad;
            if (index == 6) field.keyboardType = UIKeyboardTypeDecimalPad;
        }];
    }

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        self.configWindow.hidden = YES;
        self.configWindow = nil;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并刷新" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        NSArray<UITextField *> *fields = alert.textFields;
        NSMutableDictionary *config = [self.config mutableCopy];
        config[@"endpoint"] = fields[0].text ?: @"";
        config[@"apiKey"] = fields[1].text ?: @"";
        config[@"availablePath"] = fields[2].text.length ? fields[2].text : @"total_available";
        config[@"totalPath"] = fields[3].text ?: @"";
        config[@"usedPath"] = fields[4].text ?: @"";
        config[@"refreshInterval"] = @(MAX(15, fields[5].text.doubleValue));
        config[@"windowScale"] = @(MIN(1.50, MAX(0.75, fields[6].text.doubleValue)));
        [self saveConfig:config];
        [self applyWindowScale];
        [self scheduleRefresh];
        [self refresh];
        self.configWindow.hidden = YES;
        self.configWindow = nil;
    }]];

    [controller presentViewController:alert animated:YES completion:nil];
}

@end

__attribute__((constructor)) static void ShijianTokenBalanceInitialize(void) {
    os_log(ShijianTokenBalanceLog(), "TokenBalance loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ShijianTokenBalanceController sharedController] start];
    });
}
