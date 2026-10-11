- (void)build {
 if (self.tab == 3) {
  SettingsViewController *settings = [SettingsViewController new];
  [self addChildViewController:settings];
  settings.view.frame = self.view.bounds;
  settings.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:settings.view];
  [settings didMoveToParentViewController:self];
  [self tabs];
  return;
 }
 CGFloat w=self.view.bounds.size.width;
 CGFloat safeTop=self.view.safeAreaInsets.top;
 CGFloat headerY=safeTop+8.0;
 CGFloat largeTitleY=safeTop+66.0;
 CGFloat actionY=headerY;
 self.scroll=[[UIScrollView alloc]initWithFrame:self.view.bounds];self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;self.scroll.delegate=self;self.scroll.contentInset=UIEdgeInsetsMake(0,0,100,0);[self.view addSubview:self.scroll];
 self.content=[[UIView alloc]initWithFrame:CGRectMake(0,0,w,1700)];[self.scroll addSubview:self.content];
 self.searchRows=[NSMutableArray array];
 CGFloat y=0;
 NSString *heading=@[@"应用",@"安装包",@"插件"][self.tab];
 y=[self line:heading y:largeTitleY x:20 color:UIColor.blackColor size:37 bold:YES height:53]+8;
 self.largeTitleLabel=(UILabel *)self.content.subviews.lastObject;
 // Shared search UI; settings deliberately has no search field or reserved space.
 UISearchBar *search=[[UISearchBar alloc]initWithFrame:CGRectMake(12,y,w-24,52)];
 search.searchBarStyle=UISearchBarStyleMinimal;
 search.placeholder=@"搜索";
 search.delegate=self;
 search.searchTextField.backgroundColor=C(0xE5E5EA);
 search.searchTextField.layer.cornerRadius=12;
 search.searchTextField.clipsToBounds=YES;
 search.searchTextField.returnKeyType=UIReturnKeySearch;
 self.searchBar=search;
 [self.content addSubview:search];
 y+=62;
 self.searchRowsTop=y;
 self.normalSearchRowsTop=y;
 if(self.tab==0){
 NSArray *items=@[
 @[@"123云盘",@"3.3.2 · com.mfcloudcalculate.123networkdisk",@"cloud.fill",@"App Store"],
 @[@"阿里巴巴",@"12.11.1 · com.alibaba.wireless",@"shippingbox.fill",@"App Store"],
 @[@"阿里云盘",@"6.12.2 · com.alicloud.smartdrive",@"externaldrive.fill",@"App Store"],
 @[@"爱思全能版",@"2.2.0 · com.ownbook.notes",@"app.badge.fill",@"App Store"],
 @[@"保通双录",@"2.2.7 · com.baoinsurance.dr",@"video.fill",@"App Store"],
 @[@"必剪",@"2.91.0 · com.bilibili.studio",@"play.rectangle.fill",@"App Store"],
 @[@"哔哩哔哩",@"8.76.0 · tv.danmaku.bilianime",@"tv.fill",@"App Store"],
 @[@"Truck Simulator : Ultimate",@"1.3.7 · com.zuuks.truck.simulator.ultimate",@"truck.box.fill",@"TrollStore"],
 @[@"X",@"12.33 · com.atebits.Tweetie2",@"xmark",@"App Store"],
 @[@"XP Hero",@"26.2.0 · io.supercent.weaponrpg",@"gamecontroller.fill",@"TrollStore"],
 @[@"YouTube",@"20.02.3 · com.google.ios.youtube",@"play.rectangle.fill",@"TrollStore"],
 @[@"YY",@"8.62.0 · yyvoice",@"waveform",@"App Store"],
 @[@"zonoe",@"0.2.18 · com.GameStore.maicha.rebuild",@"pawprint.fill",@"TrollStore"],
 @[@"zonoe",@"3.0.0 · com.hfa.sign",@"pawprint.fill",@"App Store"]];
 for(NSArray *a in items)y=[self card:a[0] detail:a[1] symbol:a[2] badge:a[3] y:y];
 } else if(self.tab==1){
 y=[self card:@"1" detail:@"文件夹 · 2026-10-11 09:21（演示）" symbol:@"folder.fill" badge:nil y:y];
 y=[self card:@"Random Dice 2.ipa" detail:@"273.6 MB · 2026-10-10 02:35（演示）" symbol:@"doc.fill" badge:nil y:y];
 y=[self card:@"test.ipa" detail:@"960 KB · 2026-10-11 06:42（演示）" symbol:@"doc.fill" badge:nil y:y];
 }else{y=self.searchRowsTop;}
 CGFloat contentHeight=MAX(y,self.scroll.bounds.size.height-self.scroll.contentInset.bottom);
 self.content.frame=CGRectMake(0,0,w,contentHeight);
 self.scroll.contentSize=CGSizeMake(w,contentHeight);
 {
   UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,w,safeTop+52)];
   header.backgroundColor=C(0xF7F8FA);
   UILabel *compact=L(@[@"应用",@"安装包",@"插件",@"设置"][self.tab],20,YES,UIColor.blackColor);
   compact.textAlignment=NSTextAlignmentCenter;
   compact.frame=CGRectMake(65,safeTop+5,w-130,36);
   [header addSubview:compact];
   UIView *divider=[[UIView alloc]initWithFrame:CGRectMake(0,CGRectGetHeight(header.bounds)-0.5,w,0.5)];
   divider.backgroundColor=C(0xD0D0D4);[header addSubview:divider];
   header.alpha=0;header.userInteractionEnabled=NO;self.compactHeader=header;
   [self.view addSubview:header];
 }
 if(self.tab==1 || self.tab==2){UIButton *edit=[UIButton buttonWithType:UIButtonTypeSystem];edit.frame=CGRectMake(w-108,actionY,42,34);[edit setTitle:@"编辑" forState:UIControlStateNormal];edit.titleLabel.font=[UIFont systemFontOfSize:16];[edit addTarget:self action:@selector(demo) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:edit];}
 if(self.tab!=3){UIButton *plus=[UIButton buttonWithType:UIButtonTypeSystem];plus.frame=CGRectMake(w-53,actionY,42,42);[plus setImage:[UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:29]] forState:UIControlStateNormal];plus.tintColor=C(0x337CFA);[plus addTarget:self action:@selector(demo) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:plus];}
 [self tabs];
}
- (void)change:(UIButton*)sender {TSSkinScreen *s=[TSSkinScreen new];s.tab=sender.tag;self.view.window.rootViewController=s;}
- (void)tabs {
 CGFloat w=self.view.bounds.size.width;CGFloat dockWidth=MIN(w-112,320);
 UIView *bar=[[UIView alloc]initWithFrame:CGRectMake((w-dockWidth)/2,self.view.bounds.size.height-self.view.safeAreaInsets.bottom-72,dockWidth,60)];
 self.dock=bar;
 bar.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;bar.layer.cornerRadius=30;bar.layer.borderWidth=.5;bar.layer.borderColor=C(0xD0D0D4).CGColor;bar.backgroundColor=C(0xF9F9FB);bar.layer.shadowColor=UIColor.blackColor.CGColor;bar.layer.shadowOpacity=.08;bar.layer.shadowRadius=11;[self.view addSubview:bar];
 NSArray *names=@[@"应用",@"安装包",@"插件",@"设置"],*icons=@[@"square.grid.3x3.fill",@"shippingbox.fill",@"puzzlepiece.fill",@"gearshape.fill"];
 for(NSInteger i=0;i<4;i++){CGFloat col=dockWidth/4;UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.tag=i;b.frame=CGRectMake(i*col,2,col,38);b.tintColor=i==self.tab?C(0x337CFA):C(0x8E8E93);[b setImage:[UIImage systemImageNamed:icons[i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19]] forState:UIControlStateNormal];[b addTarget:self action:@selector(change:) forControlEvents:UIControlEventTouchUpInside];[bar addSubview:b];UILabel *t=L(names[i],10,i==self.tab,b.tintColor);t.textAlignment=NSTextAlignmentCenter;t.frame=CGRectMake(i*col,38,col,17);[bar addSubview:t];}
}
