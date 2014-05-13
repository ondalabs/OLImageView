//
//  AFImageResponseSerializer+OLImage.m
//  joke
//
//  Created by yaoandw on 14-5-13.
//  Copyright (c) 2014年 yycon. All rights reserved.
//

#import "AFImageResponseSerializer+OLImage.h"
#import <objc/runtime.h>
#import "OLImage.h"

@implementation AFImageResponseSerializer (OLImage)
- (id)responseOLImageForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error{
    return [OLImage imageWithData:data];
}
+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(responseObjectForResponse:data:error:)), class_getInstanceMethod(self, @selector(responseOLImageForResponse:data:error:)));
}
@end
