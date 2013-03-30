//
//  OLImageView.h
//  OLImageViewDemo
//
//  Created by Diego Torres on 9/5/12.
//  Copyright (c) 2012 Onda Labs. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface OLImageView : UIImageView

/**
 The animation runloop mode.
 
 @param runLoopMode The runloop mode to use. The default is NSDefaultRunLoopMode.
 
 @discussion The default mode (NSDefaultRunLoopMode), causes the animation to pauses while it is contained in an actively scrolling `UIScrollView`. Use NSRunLoopCommonModes if you don't want this behavior. 
 */
@property (nonatomic, copy) NSString *runLoopMode;

@end
