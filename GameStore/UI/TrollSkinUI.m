#import "TrollSkinUI.h"
static UIColor *C(int hex){return [UIColor colorWithRed:((hex>>16)&255)/255. green:((hex>>8)&255)/255. blue:(hex&255)/255. alpha:1];}
static UILabel *L(NSString *s,CGFloat font,BOOL bold,UIColor *color){UILabel *l=[UILabel new];l.text=s;l.textColor=color;l.font=bold?[UIFont boldSystemFontOfSize:font]:[UIFont systemFontOfSize:font];return l;}
@interface TSSkinScreen : UIViewController <UIScrollViewDelegate, UISearchBarDelegate>
@property NSInteger tab;
@property(nonatomic,strong) UIView *content;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIView *dock;
@property(nonatomic,assign) CGSize renderedSize;
@property(nonatomic,strong) UIView *compactHeader;
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) NSMutableArray<UIView *> *searchRows;
@property(nonatomic,assign) CGFloat searchRowsTop;
@property(nonatomic,strong) UIView *searchOverlay;
@property(nonatomic,assign) CGRect searchOriginalFrame;
@property(nonatomic,assign) CGFloat preSearchOffsetY;
@property(nonatomic,assign) CGFloat normalSearchRowsTop;
@property(nonatomic,strong) UILabel *largeTitleLabel;
@property(nonatomic,assign) BOOL searching;
@end
@implementation TSSkinScreen
- (void)demo {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"界面演示" message:@"当前为 UI 占位，尚未接入实际安装、插件或系统管理功能。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=C(0xF2F2F7);
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)keyboardChanged:(NSNotification *)notification {
 if (!self.searching) return;
 CGRect keyboardFrame=[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
 CGRect local=[self.view convertRect:keyboardFrame fromView:nil];
 CGFloat visible=MAX(0,MIN(self.view.bounds.size.height,CGRectGetMinY(local)));
 CGRect frame=self.scroll.frame;frame.size.height=visible;self.scroll.frame=frame;
 self.scroll.contentInset=UIEdgeInsetsMake(0,0,12,0);
}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];
 if (CGSizeEqualToSize(self.renderedSize,self.view.bounds.size)) return;
 self.renderedSize=self.view.bounds.size;
 self.searching=NO;self.searchOverlay=nil;
 for (UIView *view in [self.view.subviews copy]) [view removeFromSuperview];
 [self build];
}
#include "TSComponents.inc"
#include "TSSearch.inc"
#include "TSPages.inc"
@end

@implementation TrollSkinUI
+ (UIViewController *)createRootViewController {
 return [TSSkinScreen new];
}
@end
