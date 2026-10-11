#import "TrollSkinUI.h"
#import "GameStore-Swift.h"
static UIColor *C(int hex){return [UIColor colorWithRed:((hex>>16)&255)/255. green:((hex>>8)&255)/255. blue:(hex&255)/255. alpha:1];}
static UILabel *L(NSString *s,CGFloat font,BOOL bold,UIColor *color){UILabel *l=[UILabel new];l.text=s;l.textColor=color;l.font=bold?[UIFont boldSystemFontOfSize:font]:[UIFont systemFontOfSize:font];return l;}
@interface TSSkinScreen : UIViewController <UIScrollViewDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
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
@property(nonatomic,strong) UITableView *catalogTable;
@property(nonatomic,strong) NSArray<NSDictionary<NSString *,NSString *> *> *catalogItems;
@property(nonatomic,strong) NSArray<NSDictionary<NSString *,NSString *> *> *visibleCatalogItems;
@end
@implementation TSSkinScreen
- (void)demo {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"界面演示" message:@"当前为 UI 占位，尚未接入实际安装、插件或系统管理功能。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=C(0xF2F2F7);
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceCatalogChanged:) name:@"GameStoreSourceCatalogDidChange" object:nil];
 if (self.tab==0) { [SourceCatalogUIBridge start]; [SourceCatalogUIBridge refresh]; }
}
- (void)sourceCatalogChanged:(NSNotification *)notification {
 if (self.tab != 0 || !self.isViewLoaded) return;
 self.catalogItems = [SourceCatalogUIBridge entries];
 [self filterCatalog:self.searchBar.text ?: @""];
 [self.catalogTable reloadData];
 if (self.catalogTable) {
  self.catalogTable.backgroundView = self.visibleCatalogItems.count ? nil : [self catalogEmptyView];
 }
}
- (UIView *)catalogEmptyView {
 UILabel *empty=L([SourceCatalogUIBridge hasSources]?@"暂无软件源应用（正在同步或软件源为空）":@"尚未添加软件源，请前往「设置 → 软件源」添加",15,NO,C(0x8E8E93));
 empty.textAlignment=NSTextAlignmentCenter;empty.numberOfLines=0;
 empty.frame=CGRectMake(20,60,self.view.bounds.size.width-40,90);
 UIView *holder=[[UIView alloc]initWithFrame:self.catalogTable.bounds];
 [holder addSubview:empty];
 return holder;
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
 for (UIViewController *child in [self.childViewControllers copy]) {
  [child willMoveToParentViewController:nil];
  [child.view removeFromSuperview];
  [child removeFromParentViewController];
 }
 for (UIView *view in [self.view.subviews copy]) [view removeFromSuperview];
 [self build];
}
- (void)filterCatalog:(NSString *)query {
 NSString *needle=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if (needle.length == 0) { self.visibleCatalogItems=self.catalogItems; return; }
 NSPredicate *predicate=[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
  NSString *key=[NSString stringWithFormat:@"%@ %@",item[@"name"]?:@"",item[@"detail"]?:@""];
  return [key rangeOfString:needle options:NSCaseInsensitiveSearch].location!=NSNotFound;
 }];
 self.visibleCatalogItems=[self.catalogItems filteredArrayUsingPredicate:predicate];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleCatalogItems.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 78; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
 AppCatalogCell *cell=[tableView dequeueReusableCellWithIdentifier:@"SourceApp"];
 if (!cell) cell=[[AppCatalogCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SourceApp"];
 NSDictionary<NSString *,NSString *> *app=self.visibleCatalogItems[indexPath.row];
 [cell configureWithName:app[@"name"]?:@"" detail:app[@"detail"]?:@"" category:app[@"category"]?:@"" iconURL:app[@"iconURL"]?:@""];
 return cell;
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
