//
//  AFImageRequestOperation+OLImage.m
//  MMTmini
//
//  Created by Diego Torres on 16-10-12.
//  Copyright (c) 2012 Onda. All rights reserved.
//

#import "AFImageRequestOperation+OLImage.h"
#import <objc/runtime.h>
#import "OLImage.h"

@implementation AFImageRequestOperation (OLImage)

- (void)setResponseOLImage:(UIImage *)responseImage {
    if ([self.responseData length] > 0 && [self isFinished]) {
        [self setResponseOLImage:[OLImage imageWithData:self.responseData]];
    }
}

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(setResponseImage:)), class_getInstanceMethod(self, @selector(setResponseOLImage:)));
}

@end
