//
//  OLImage.m
//  MMT
//
//  Created by Diego Torres on 9/1/12.
//  Copyright (c) 2012 Onda. All rights reserved.
//

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "OLImage.h"

inline static double CGImageSourceGetGifFrameDelay(CGImageSourceRef imageSource, NSUInteger index)
{
    double frameDuration = 0.0f;
    
    CFDictionaryRef theImageProperties;
    if ((theImageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, NULL))) {
        CFDictionaryRef gifProperties;
        if (CFDictionaryGetValueIfPresent(theImageProperties, kCGImagePropertyGIFDictionary, (const void **)&gifProperties)) {
            const void *frameDurationValue;
            if (CFDictionaryGetValueIfPresent(gifProperties, kCGImagePropertyGIFUnclampedDelayTime, &frameDurationValue)) {
                frameDuration = [(__bridge NSNumber *)frameDurationValue floatValue];
                if (frameDuration <= 0) {
                    if (CFDictionaryGetValueIfPresent(gifProperties, kCGImagePropertyGIFDelayTime, &frameDurationValue)) {
                        frameDuration = [(__bridge NSNumber *)frameDurationValue floatValue];
                    }
                }
            }
        }
        CFRelease(theImageProperties);
    }
    
    return frameDuration;
}

inline static BOOL CGImageSourceGetFramesAndDurations(NSTimeInterval *finalDuration, NSTimeInterval *frameDurations, NSMutableArray *arrayToFill, CGImageSourceRef imageSource)
{
    BOOL evenFrameDuration = YES;
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    for (NSUInteger i = 0; i < numberOfFrames; ++i) {
        
        //Implement as Browsers do, to ensure UX.
        //See: http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
        //See also: http://blogs.msdn.com/b/ieinternals/archive/2010/06/08/animated-gifs-slow-down-to-under-20-frames-per-second.aspx
        double proposedFrameDuration = CGImageSourceGetGifFrameDelay(imageSource, i);
        #ifndef OLExactGIFRepresentation
        proposedFrameDuration = (proposedFrameDuration >= 0.02) ? proposedFrameDuration : 0.10f;
        #endif
        frameDurations[i] = proposedFrameDuration;
        
        if (evenFrameDuration && i > 0 && frameDurations[i] != frameDurations[i-1]) {
            evenFrameDuration = NO;
        }
        
        CGImageRef theImage = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
        [arrayToFill addObject:[UIImage imageWithCGImage:theImage]];
        CFRelease(theImage);
        if (finalDuration) {
            *finalDuration += frameDurations[i];
        }
    }
    
    return evenFrameDuration;
}

@interface OLImage ()

@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;
@property (nonatomic, readwrite) NSMutableArray *images;

@end

@implementation OLImage
@synthesize frameDurations, images;
@synthesize totalDuration = _totalDuration;


+ (id)imageWithData:(NSData *)data
{
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    if (!imageSource) {
        return nil;
    }
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    if (!UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF) || numberOfFrames == 1) {
        CFRelease(imageSource);
        return [UIImage imageWithData:data];
    }
    
    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyProperties(imageSource, NULL));
    NSDictionary *GIFProperties = [imageProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
    
    OLImage *animatedImage = [[OLImage  alloc] init];
    animatedImage.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
    animatedImage.frameDurations = (NSTimeInterval *) malloc(numberOfFrames  * sizeof(NSTimeInterval));
    animatedImage.totalDuration = 0.0f;
    animatedImage.loopCount = [GIFProperties[(NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    
    //Load First Frame
    double proposedFrameDuration = CGImageSourceGetGifFrameDelay(imageSource, 0);
#ifndef OLExactGIFRepresentation
    proposedFrameDuration = (proposedFrameDuration >= 0.02) ? proposedFrameDuration : 0.10f;
#endif
    animatedImage.frameDurations[0] = proposedFrameDuration;
    
    CGImageRef theImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    [animatedImage.images addObject:[UIImage imageWithCGImage:theImage]];
    CFRelease(theImage);
    animatedImage.totalDuration += animatedImage.frameDurations[0];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        BOOL evenFrameDuration = YES;
        NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
        for (NSUInteger i = 1; i < numberOfFrames; ++i) {
            
            //Implement as Browsers do, to ensure UX.
            //See: http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
            //See also: http://blogs.msdn.com/b/ieinternals/archive/2010/06/08/animated-gifs-slow-down-to-under-20-frames-per-second.aspx
            double proposedFrameDuration = CGImageSourceGetGifFrameDelay(imageSource, i);
#ifndef OLExactGIFRepresentation
            proposedFrameDuration = (proposedFrameDuration >= 0.02) ? proposedFrameDuration : 0.10f;
#endif
            animatedImage.frameDurations[i] = proposedFrameDuration;
            
            if (evenFrameDuration && i > 0 && animatedImage.frameDurations[i] != animatedImage.frameDurations[i-1]) {
                evenFrameDuration = NO;
            }
            
            CGImageRef theImage = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
            [animatedImage.images addObject:[UIImage imageWithCGImage:theImage]];
            CFRelease(theImage);
            animatedImage.totalDuration += animatedImage.frameDurations[i];
        }
        
        CFRelease(imageSource);
    });
    
    return animatedImage;
}

- (id)initWithData:(NSData *)data {
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    
    if (!UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF)) {
        CFRelease(imageSource);
        return [super initWithData:data];
    }
    
    if (imageSource) {
        NSTimeInterval *aFinalDuration = NULL;
        NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
        self.frameDurations = (NSTimeInterval *) malloc(numberOfFrames  * sizeof(NSTimeInterval));
        self.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
        CGImageSourceGetFramesAndDurations(aFinalDuration, self.frameDurations, self.images, imageSource);
        if (aFinalDuration) {
            _totalDuration = *aFinalDuration;
        }
        CFRelease(imageSource);
        return self;
    }
    return nil;
    
}

- (CGSize)size
{
    if (images) {
        return [[images objectAtIndex:0] size];
    }
    return [super size];
}

- (NSTimeInterval)duration {
    return 0;
}

-(void)dealloc {
    free(frameDurations);
}

@end
