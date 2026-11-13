#import <UIKit/UIKit.h>

@interface CCUIToggleModule : NSObject
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
- (UIImage *)iconGlyph;
- (UIColor *)selectedColor;
@end
