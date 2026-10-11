- (CGFloat)line:(NSString*)text y:(CGFloat)y x:(CGFloat)x color:(UIColor*)color size:(CGFloat)size bold:(BOOL)bold height:(CGFloat)h {
 UILabel *l=L(text,size,bold,color);l.numberOfLines=0;l.frame=CGRectMake(x,y,self.view.bounds.size.width-2*x,h);[self.content addSubview:l];return y+h;
}
- (CGFloat)card:(NSString*)name detail:(NSString*)detail symbol:(NSString*)symbol badge:(NSString*)badge y:(CGFloat)y {
 CGFloat w=self.view.bounds.size.width;
 UIView *v=[[UIView alloc]initWithFrame:CGRectMake(18,y,w-36,70)];v.backgroundColor=UIColor.whiteColor;v.layer.cornerRadius=16;[self.content addSubview:v];
 UIView *ic=[[UIView alloc]initWithFrame:CGRectMake(13,12,46,46)];ic.backgroundColor=C(0xE6F0FF);ic.layer.cornerRadius=11;[v addSubview:ic];
 UIImageView *iv=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol?:@"app.fill"]];iv.tintColor=C(0x337CFA);iv.contentMode=UIViewContentModeScaleAspectFit;iv.frame=CGRectInset(ic.bounds,10,10);[ic addSubview:iv];
 UILabel *t=L(name,15,YES,UIColor.blackColor);t.frame=CGRectMake(72,8,w-118,22);[v addSubview:t];
 UILabel *d=L(detail,11,NO,C(0x8E8E93));d.adjustsFontSizeToFitWidth=YES;d.minimumScaleFactor=.75;d.frame=CGRectMake(72,28,w-116,17);[v addSubview:d];
 if(badge){UILabel *b=L(badge,10,NO,[badge isEqual:@"TrollStore"]?C(0x36B85A):C(0x337CFA));b.backgroundColor=[badge isEqual:@"TrollStore"]?C(0xE7F8EB):C(0xE6F0FF);b.textAlignment=NSTextAlignmentCenter;b.layer.cornerRadius=5;b.clipsToBounds=YES;b.frame=CGRectMake(72,49,[badge isEqual:@"TrollStore"]?68:60,16);[v addSubview:b];}
 UIButton *tap=[UIButton buttonWithType:UIButtonTypeCustom];tap.frame=v.bounds;[tap addTarget:self action:@selector(demo) forControlEvents:UIControlEventTouchUpInside];[v addSubview:tap];
 v.accessibilityIdentifier=[NSString stringWithFormat:@"%@ %@",name,detail];
 [self.searchRows addObject:v];
 return y+78;
}
- (CGFloat)setting:(NSString*)name icon:(NSString*)icon color:(UIColor*)color y:(CGFloat)y {
 CGFloat w=self.view.bounds.size.width;UIView *v=[[UIView alloc]initWithFrame:CGRectMake(18,y,w-36,50)];v.backgroundColor=UIColor.whiteColor;v.layer.cornerRadius=19;[self.content addSubview:v];
 UIImageView *iv=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:icon]];iv.frame=CGRectMake(23,13,24,24);iv.tintColor=color;iv.contentMode=UIViewContentModeScaleAspectFit;[v addSubview:iv];
 UILabel *lab=L(name,16,NO,color);lab.frame=CGRectMake(63,6,w-107,38);lab.adjustsFontSizeToFitWidth=YES;lab.minimumScaleFactor=.7;[v addSubview:lab];
 UIButton *tap=[UIButton buttonWithType:UIButtonTypeCustom];tap.frame=v.bounds;[tap addTarget:self action:@selector(demo) forControlEvents:UIControlEventTouchUpInside];[v addSubview:tap];return y+59;
}
