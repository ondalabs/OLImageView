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

inline static NSTimeInterval CGImageSourceGetGifFrameDelay(CGImageSourceRef imageSource, NSUInteger index)
{
    NSTimeInterval frameDuration = 0;
    CFDictionaryRef theImageProperties;
    if ((theImageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, NULL))) {
        CFDictionaryRef gifProperties;
        if (CFDictionaryGetValueIfPresent(theImageProperties, kCGImagePropertyGIFDictionary, (const void **)&gifProperties)) {
            const void *frameDurationValue;
            if (CFDictionaryGetValueIfPresent(gifProperties, kCGImagePropertyGIFUnclampedDelayTime, &frameDurationValue)) {
                frameDuration = [(__bridge NSNumber *)frameDurationValue doubleValue];
                if (frameDuration <= 0) {
                    if (CFDictionaryGetValueIfPresent(gifProperties, kCGImagePropertyGIFDelayTime, &frameDurationValue)) {
                        frameDuration = [(__bridge NSNumber *)frameDurationValue doubleValue];
                    }
                }
            }
        }
        CFRelease(theImageProperties);
    }
    
#ifndef OLExactGIFRepresentation
    //Implement as Browsers do.
    //See:  http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
    //Also: http://blogs.msdn.com/b/ieinternals/archive/2010/06/08/animated-gifs-slow-down-to-under-20-frames-per-second.aspx
    
    if (frameDuration < 0.02 - FLT_EPSILON) {
        frameDuration = 0.1;
    }
#endif
    return frameDuration;
}

inline static NSTimeInterval CGImageSourceGetFramesAndDurations(NSTimeInterval *frameDurations, NSMutableArray *arrayToFill, CGImageSourceRef imageSource, NSUInteger numberOfFrames)
{
    NSTimeInterval finalDuration = 0;
    for (NSUInteger i = 0; i < numberOfFrames; ++i) {
        frameDurations[i] = CGImageSourceGetGifFrameDelay(imageSource, i);
        CGImageRef theImage = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
        [arrayToFill addObject:[UIImage imageWithCGImage:theImage]];
        CFRelease(theImage);
        finalDuration += frameDurations[i];
    }
    return finalDuration;
}

@interface OLImage ()

@property (nonatomic, readwrite) NSMutableArray *images;
@property (nonatomic, readwrite) NSTimeInterval *frameDurations;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;

@end

@implementation OLImage

@synthesize images;

+ (id)imageWithData:(NSData *)data
{
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    if (!imageSource) {
        return [UIImage imageWithData:data];
    }
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    if (numberOfFrames == 1 || !UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF)) {
        CFRelease(imageSource);
        return [UIImage imageWithData:data];
    }
    
    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyProperties(imageSource, NULL));
    NSDictionary *GIFProperties = [imageProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
    
    OLImage *animatedImage = [[OLImage  alloc] init];
    animatedImage.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
    animatedImage.frameDurations = (NSTimeInterval *)malloc(numberOfFrames  * sizeof(NSTimeInterval));
    animatedImage.totalDuration = 0.0;
    animatedImage.loopCount = [GIFProperties[(NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    
    //Load First Frame
    animatedImage.frameDurations[0] = CGImageSourceGetGifFrameDelay(imageSource, 0);
    
    CGImageRef firstImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    [animatedImage.images addObject:[UIImage imageWithCGImage:firstImage]];
    CFRelease(firstImage);
    animatedImage.totalDuration += animatedImage.frameDurations[0];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 1; i < numberOfFrames; ++i) {
            animatedImage.frameDurations[i] = CGImageSourceGetGifFrameDelay(imageSource, i);
            CGImageRef frameImage = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
            [animatedImage.images addObject:[UIImage imageWithCGImage:frameImage]];
            CFRelease(frameImage);
            animatedImage.totalDuration += animatedImage.frameDurations[i];
        }
        
        CFRelease(imageSource);
    });
    
    return animatedImage;
}

- (id)initWithData:(NSData *)data {
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    
    if (!imageSource) {
        return nil;
    }
    
    if (!UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF)) {
        CFRelease(imageSource);
        return [super initWithData:data];
    }
    
    self = [super init];
    
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    
    self.frameDurations = (NSTimeInterval *) malloc(numberOfFrames  * sizeof(NSTimeInterval));
    self.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
    self.totalDuration = CGImageSourceGetFramesAndDurations(self.frameDurations, self.images, imageSource, numberOfFrames);
    
    CFRelease(imageSource);
    return self;
}

+ (UIImage *)imageNamed:(NSString *)name
{
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
    
    return ([[NSFileManager defaultManager] fileExistsAtPath:path]) ? [OLImage imageWithContentsOfFile:path] : nil;
}

+ (UIImage *)imageWithContentsOfFile:(NSString *)path
{
    return [OLImage imageWithData:[NSData dataWithContentsOfFile:path]];
}

- (CGSize)size
{
    if (self.images.count) {
        return [[self.images objectAtIndex:0] size];
    }
    return [super size];
}

- (CGImageRef)CGImage
{
    if (self.images.count) {
        return [[self.images objectAtIndex:0] CGImage];
    } else {
        return [super CGImage];
    }
}

- (UIImageOrientation)imageOrientation
{
    if (self.images.count) {
        return [[self.images objectAtIndex:0] imageOrientation];
    } else {
        return [super imageOrientation];
    }
}

- (CGFloat)scale
{
    if (self.images.count) {
        return [(UIImage *)[self.images objectAtIndex:0] scale];
    } else {
        return [super scale];
    }
}

- (NSTimeInterval)duration
{
    return self.images ? self.totalDuration : [super duration];
}

- (void)dealloc {
    free(_frameDurations);
}

@end
