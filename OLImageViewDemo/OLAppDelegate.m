//
//  OLAppDelegate.m
//  OLImageViewDemo
//
//  Created by Diego Torres on 9/5/12.
//  Copyright (c) 2012 Onda Labs. All rights reserved.
//

#import "OLAppDelegate.h"
#import "OLImageView.h"
#import "OLImage.h"

#import <AFNetworking/UIImageView+AFNetworking.h>
#import "OLImageResponseSerializer.h"
#import "OLImageStrictResponseSerializer.h"

#import "OLImageViewDelegate.h"

#define OLDemoShowAnimationTickers 0

@interface OLAppDelegate ()<OLImageViewDelegate>

@property (nonatomic, getter=isRunning) BOOL running;

@end

@implementation OLAppDelegate

-(BOOL)imageViewShouldStartAnimating:(OLImageView *)imageView {
    
    return self.isRunning;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *normalAnimatedVC = [UIViewController new];
    normalAnimatedVC.title = @"UIImageView";
    UIImageView *imv = [[UIImageView alloc] initWithImage:[UIImage animatedImageNamed:@"BB" duration:1.6]];
    normalAnimatedVC.view = imv;
    
    UIViewController *magicAnimatedVC = [UIViewController new];
    magicAnimatedVC.title = @"OLImageView";
    
    OLImageView *Aimv = [[OLImageView alloc] initWithImage:[OLImage imageNamed:@"notEven.gif"]];
    [Aimv setFrame:CGRectMake(0, 0, 160, 160)];
    [Aimv setUserInteractionEnabled:YES];
    [Aimv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
    [magicAnimatedVC.view addSubview:Aimv];
    
    Aimv = [[OLImageView alloc] initWithImage:[OLImage imageNamed:@"google-io"]];
    Aimv.contentMode = UIViewContentModeCenter;
    Aimv.clipsToBounds = YES;
    [Aimv setFrame:CGRectMake(0, 160, 160, 160)];
    [Aimv setUserInteractionEnabled:YES];
    [Aimv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
    [magicAnimatedVC.view addSubview:Aimv];
    
    Aimv = [[OLImageView alloc] initWithImage:[OLImage imageNamed:@"fdgdf.gif"]];
    [Aimv setFrame:CGRectMake(160, 0, 160, 160)];
    [Aimv setUserInteractionEnabled:YES];
    [Aimv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
    [magicAnimatedVC.view addSubview:Aimv];
    
    Aimv = [[OLImageView alloc] initWithImage:[OLImage imageNamed:@"AA.gif"]];
    Aimv.delegate = self;
    [Aimv setFrame:CGRectMake(160, 160, 160, 160)];
    [Aimv setUserInteractionEnabled:YES];
    [Aimv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
    [magicAnimatedVC.view addSubview:Aimv];
    
#if OLDemoShowAnimationTickers
    // GIFs from http://blog.fenrir-inc.com/us/2012/02/theyre-different-how-to-match-the-animation-rate-of-gif-files-accross-browsers.html
    for (NSUInteger i = 1; i <= 10; i++) {
        NSString *filename = [NSString stringWithFormat:@"%u.gif", i];
        OLImageView *frameCountImage = [[OLImageView alloc] initWithImage:[OLImage imageNamed:filename]];
        [frameCountImage setFrame:CGRectMake((i - 1) * 32, 320, 32, 32)];
        [magicAnimatedVC.view addSubview:frameCountImage];
    }
#endif
    
    UIViewController *magicAnimatedVCnet = [UIViewController new];
    magicAnimatedVCnet.title = @"OLImageView+AFNet2";
    UIImageView *imgV = [UIImageView new];
    imgV.imageResponseSerializer = [OLImageResponseSerializer new];
    imgV.frame = CGRectMake(0, 0, 320, 240);
    [magicAnimatedVCnet.view addSubview:imgV];
    
    // First image uses easy one-for-all serializer and is suitable for all images, losing some AFNetworking behavior
    [imgV setImageWithURL:[NSURL URLWithString:@"http://24.media.tumblr.com/9a7e2652afde1fbe7b1d2e978be64765/tumblr_mke4w2g7C31qz8x31o1_400.gif"]];
    
    imgV = [UIImageView new];
    AFCompoundResponseSerializer *compoundSerializer = [AFCompoundResponseSerializer compoundSerializerWithResponseSerializers:@[[OLImageStrictResponseSerializer new], imgV.imageResponseSerializer]];
    imgV.imageResponseSerializer = compoundSerializer;
    imgV.frame = CGRectMake(0, 240, 320, 240);
    [magicAnimatedVCnet.view addSubview:imgV];
    
    // Second image uses compound serializer, is suitable for both gifs and images and support any number of serializers
    [imgV setImageWithURL:[NSURL URLWithString:@"http://24.media.tumblr.com/9a7e2652afde1fbe7b1d2e978be64765/tumblr_mke4w2g7C31qz8x31o1_400.gif"]];
    
    UITabBarController *tbc = [[UITabBarController alloc] init];
    [tbc setViewControllers:@[normalAnimatedVC, magicAnimatedVC, magicAnimatedVCnet]];
    
    self.window.rootViewController = tbc;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)handleTap:(UITapGestureRecognizer *)gestRecon
{
    OLImageView *imageView = (OLImageView *)gestRecon.view;
    if (self.isRunning) {
        self.running = NO;
        NSLog(@"STOP");
        [imageView stopAnimating];
    } else {
        self.running = YES;
        NSLog(@"START");
        [imageView startAnimating];
    }
}

@end
