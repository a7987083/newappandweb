- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
 if (self.tab==3 || self.searching) return YES;
 self.searching=YES;
 CGFloat w=self.view.bounds.size.width;
 CGFloat safeTop=self.view.safeAreaInsets.top;
 self.preSearchOffsetY=self.scroll.contentOffset.y;
 self.searchOriginalFrame=searchBar.frame;
 CGRect startFrame=[searchBar.superview convertRect:searchBar.frame toView:self.view];
 UIView *overlay=[[UIView alloc]initWithFrame:CGRectMake(0,0,w,safeTop+61)];
 overlay.backgroundColor=C(0xF7F8FA);
 overlay.alpha=0;
 self.searchOverlay=overlay;
 [self.view addSubview:overlay];
 [searchBar removeFromSuperview];
 searchBar.frame=startFrame;
 [overlay addSubview:searchBar];
 UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];
 cancel.frame=CGRectMake(w-75,safeTop+5,68,49);
 [cancel setTitle:@"取消" forState:UIControlStateNormal];
 cancel.titleLabel.font=[UIFont systemFontOfSize:16];
 cancel.alpha=0;
 [cancel addTarget:self action:@selector(cancelSearch) forControlEvents:UIControlEventTouchUpInside];
 [overlay addSubview:cancel];
 UIView *separator=[[UIView alloc]initWithFrame:CGRectMake(0,safeTop+60,w,0.5)];
 separator.backgroundColor=C(0xD0D0D4);[overlay addSubview:separator];
 self.compactHeader.hidden=YES;
 self.largeTitleLabel.hidden=YES;
 // Remove the collapsed large-title/search placeholder area while editing.
 self.searchRowsTop=safeTop+70;
 [self searchBar:searchBar textDidChange:searchBar.text?:@""];
 [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState animations:^{
   overlay.alpha=1;
   searchBar.frame=CGRectMake(12,safeTop+5,w-93,49);
   cancel.alpha=1;
   self.dock.alpha=0;
   [self.scroll setContentOffset:CGPointZero animated:NO];
 } completion:^(BOOL finished) {
   if(self.searching) self.dock.hidden=YES;
 }];
 return YES;
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
 [searchBar resignFirstResponder];
}
- (void)cancelSearch {
 // Preserve the position reached while browsing search results, not the
 // position saved before search began. Capture it before changing row geometry.
 CGFloat visibleOffset=self.scroll.contentOffset.y;
 self.searching=NO; // Ignore the asynchronous keyboard-hide notification.
 [self.searchBar resignFirstResponder];
 self.searchBar.text=@"";
 self.searchRowsTop=self.normalSearchRowsTop;
 self.scroll.frame=self.view.bounds;
 self.scroll.contentInset=UIEdgeInsetsMake(0,0,100,0);
 [self searchBar:self.searchBar textDidChange:@""];
 CGFloat minOffset=-self.scroll.adjustedContentInset.top;
 CGFloat maxOffset=MAX(minOffset,self.scroll.contentSize.height-self.scroll.bounds.size.height+self.scroll.adjustedContentInset.bottom);
 CGFloat targetY=MIN(MAX(visibleOffset,minOffset),maxOffset);
 [self.scroll setContentOffset:CGPointMake(0,targetY) animated:NO];
 CGRect restore=[self.content convertRect:self.searchOriginalFrame toView:self.view];
 self.dock.hidden=NO;
 [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState animations:^{
   self.searchBar.frame=restore;
   self.searchOverlay.alpha=0;
   self.dock.alpha=1;
 } completion:^(BOOL finished) {
   // Complete cleanup even if the animation was interrupted.
   [self.searchBar removeFromSuperview];
   self.searchBar.frame=self.searchOriginalFrame;
   [self.content addSubview:self.searchBar];
   [self.searchOverlay removeFromSuperview];
   self.searchOverlay=nil;
   self.compactHeader.hidden=NO;
   self.largeTitleLabel.hidden=NO;
   // Re-apply after UIKit's keyboard/layout updates settle.
   CGFloat minY=-self.scroll.adjustedContentInset.top;
   CGFloat maxY=MAX(minY,self.scroll.contentSize.height-self.scroll.bounds.size.height+self.scroll.adjustedContentInset.bottom);
   [self.scroll setContentOffset:CGPointMake(0,MIN(MAX(targetY,minY),maxY)) animated:NO];
   [self scrollViewDidScroll:self.scroll];
 }];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
 NSString *needle=[searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 CGFloat y=self.searchRowsTop;
 for (UIView *row in self.searchRows) {
   BOOL match=needle.length==0 || [row.accessibilityIdentifier rangeOfString:needle options:NSCaseInsensitiveSearch].location!=NSNotFound;
   row.hidden=!match;
   if (match) { CGRect f=row.frame;f.origin.y=y;row.frame=f;y+=78; }
 }
 CGFloat h=MAX(y,self.scroll.bounds.size.height-self.scroll.contentInset.bottom);
 self.content.frame=CGRectMake(0,0,self.view.bounds.size.width,h);
 self.scroll.contentSize=CGSizeMake(self.view.bounds.size.width,h);
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
 if (!self.compactHeader || self.searching) return;
 // The large title scrolls out; the compact title stays fixed below the status bar.
 CGFloat progress=MIN(1.0,MAX(0.0,(scrollView.contentOffset.y-18.0)/28.0));
 self.compactHeader.alpha=progress;
}
