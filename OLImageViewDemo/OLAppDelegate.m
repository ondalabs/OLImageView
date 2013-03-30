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

#define OLDemoShowAnimationTickers YES

@implementation OLAppDelegate

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
    
    Aimv = [[OLImageView alloc] initWithImage:[OLImage imageNamed:@"BLEH.gif"]];
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
    
    UITabBarController *tbc = [[UITabBarController alloc] init];
    [tbc setViewControllers:@[normalAnimatedVC, magicAnimatedVC]];
    
    self.window.rootViewController = tbc;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)handleTap:(UITapGestureRecognizer *)gestRecon
{
    OLImageView *imageView = (OLImageView *)gestRecon.view;
    if (imageView.isAnimating) {
        NSLog(@"STOP");
        [imageView stopAnimating];
    } else {
         NSLog(@"START");
        [imageView startAnimating];
    }
}

@end
