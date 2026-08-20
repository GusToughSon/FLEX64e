#import <UIKit/UIKit.h>
@interface PSViewController : UIViewController
@end
@interface PSListController : PSViewController
- (void)loadView;
@property (nonatomic, strong) NSMutableArray *specifiers;
@end
