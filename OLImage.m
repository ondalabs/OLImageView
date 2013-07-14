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

inline static BOOL CGImageSourceContainsAnimatedGif(CGImageSourceRef imageSource)
{
    return imageSource && UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF) && CGImageSourceGetCount(imageSource) > 1;
}

inline static BOOL isRetinaFilePath(NSString *path)
{
    NSRange retinaSuffixRange = [[path lastPathComponent] rangeOfString:@"@2x" options:NSCaseInsensitiveSearch];
    return retinaSuffixRange.length && retinaSuffixRange.location != NSNotFound;
}

@interface OLImage ()

@property (nonatomic, readwrite) NSMutableArray *images;
@property (nonatomic, readwrite) NSTimeInterval *frameDurations;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;
@property (nonatomic, readwrite) CGImageSourceRef incrementalSource;

@end

@implementation OLImage

@synthesize images;

#pragma mark - Class Methods

+ (id)imageNamed:(NSString *)name
{
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
    
    return ([[NSFileManager defaultManager] fileExistsAtPath:path]) ? [self imageWithContentsOfFile:path] : nil;
}

+ (id)imageWithContentsOfFile:(NSString *)path
{
    return [self imageWithData:[NSData dataWithContentsOfFile:path]
                         scale:isRetinaFilePath(path) ? 2.0f : 1.0f];
}

+ (id)imageWithData:(NSData *)data
{
    return [self imageWithData:data scale:1.0f];
}

+ (id)imageWithData:(NSData *)data scale:(CGFloat)scale
{
    if (!data) {
        return nil;
    }
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    UIImage *image;
    
    if (CGImageSourceContainsAnimatedGif(imageSource)) {
        image = [[self alloc] initWithCGImageSource:imageSource scale:scale];
    } else {
        image = [super imageWithData:data scale:scale];
    }
    
    if (imageSource) {
        CFRelease(imageSource);
    }
    
    return image;
}

#pragma mark - Initialization methods

- (id)initWithContentsOfFile:(NSString *)path
{
    return [self initWithData:[NSData dataWithContentsOfFile:path]
                        scale:isRetinaFilePath(path) ? 2.0f : 1.0f];
}

- (id)initWithData:(NSData *)data
{
    return [self initWithData:data scale:1.0f];
}

- (id)initWithData:(NSData *)data scale:(CGFloat)scale
{
    if (!data) {
        return nil;
    }
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    
    if (CGImageSourceContainsAnimatedGif(imageSource)) {
        self = [self initWithCGImageSource:imageSource scale:scale];
    } else {
        if (scale == 1.0f) {
            self = [super initWithData:data];
        } else {
            self = [super initWithData:data scale:scale];
        }
    }
    
    if (imageSource) {
        CFRelease(imageSource);
    }
    
    return self;
}

- (id)initWithCGImageSource:(CGImageSourceRef)imageSource scale:(CGFloat)scale
{
    self = [super init];
    if (!imageSource || !self) {
        return nil;
    }
    
    CFRetain(imageSource);
    
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    
    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyProperties(imageSource, NULL));
    NSDictionary *gifProperties = [imageProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
    
    self.frameDurations = (NSTimeInterval *)malloc(numberOfFrames  * sizeof(NSTimeInterval));
    self.loopCount = [gifProperties[(NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    self.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
    
    // Load first frame
    CGImageRef firstImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    [self.images addObject:[UIImage imageWithCGImage:firstImage scale:scale orientation:UIImageOrientationUp]];
    CFRelease(firstImage);
    
    NSTimeInterval firstFrameDuration = CGImageSourceGetGifFrameDelay(imageSource, 0);
    self.frameDurations[0] = firstFrameDuration;
    self.totalDuration = firstFrameDuration;
    
    // Asynchronously load the remaining frames
    __weak OLImage *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 1; i < numberOfFrames; ++i) {
            OLImage *strongSelf = weakSelf;
            if (!strongSelf) {
                break;
            }
            NSTimeInterval frameDuration = CGImageSourceGetGifFrameDelay(imageSource, i);
            strongSelf.frameDurations[i] = frameDuration;
            strongSelf.totalDuration += frameDuration;
            
            CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
            [strongSelf.images addObject:[UIImage imageWithCGImage:frameImageRef scale:scale orientation:UIImageOrientationUp]];
            CFRelease(frameImageRef);
        }
        CFRelease(imageSource);
    });
    
    return self;
}

#pragma mark - Compatibility methods

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
    if (_incrementalSource) {
        CFRelease(_incrementalSource);
    }
}

@end

@implementation OLImage (IncrementalData)

//Snippet from AFNetworking
static inline CGImageRef OLDecodedCGImageFromCGImage(CGImageRef imageRef)
{
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    size_t bitsPerComponent = CGImageGetBitsPerComponent(imageRef);
    size_t bytesPerRow = 0; // CGImageGetBytesPerRow() calculates incorrectly in iOS 5.0, so defer to CGBitmapContextCreate()
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
    
    if (CGColorSpaceGetNumberOfComponents(colorSpace) == 3) {
        int alpha = (bitmapInfo & kCGBitmapAlphaInfoMask);
        if (alpha == kCGImageAlphaNone) {
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaNoneSkipFirst;
        } else if (!(alpha == kCGImageAlphaNoneSkipFirst || alpha == kCGImageAlphaNoneSkipLast)) {
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaPremultipliedFirst;
        }
    }
    
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
    
    CGColorSpaceRelease(colorSpace);
    
    CGRect rect = CGRectMake(0.0f, 0.0f, width, height);
    CGContextDrawImage(context, rect, imageRef);
    CGImageRef decodedImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return decodedImage;
}

+ (instancetype)imageWithIncrementalData:(NSData *)data
{
    OLImage *image = [[OLImage alloc] init];
    image.totalDuration = 0;
    image.incrementalSource = CGImageSourceCreateIncremental(NULL);
    image.images = [NSMutableArray new];
    if (data) {
        [image updateWithData:data];
    }
    return image;
}

- (void)updateWithData:(NSData *)data
{
    [self updateWithData:data final:NO];
}

- (void)updateWithData:(NSData *)data final:(BOOL)final
{
    if (![self isPartial]) {
        return;
    }
    NSInteger currentlyDecodedIndex = self.images ? ([self.images count] - 1) : -1;
    CGImageSourceUpdateData(_incrementalSource, (__bridge CFDataRef)(data), final);
    NSUInteger imageCount = CGImageSourceGetCount(_incrementalSource);
    while ((imageCount > currentlyDecodedIndex + 2) || (final && imageCount > currentlyDecodedIndex+1)) {
        currentlyDecodedIndex += 1;
        
        NSTimeInterval delay = CGImageSourceGetGifFrameDelay(_incrementalSource, currentlyDecodedIndex);        
        NSTimeInterval *oldDelayArray = self.frameDurations;
        NSTimeInterval *newDelayArray = (NSTimeInterval *)malloc((currentlyDecodedIndex + 1)*sizeof(NSTimeInterval));
        memcpy(newDelayArray, oldDelayArray, currentlyDecodedIndex*sizeof(NSTimeInterval));
        newDelayArray[currentlyDecodedIndex] = delay;
        self.frameDurations = newDelayArray;
        self.totalDuration += delay;
        
        CGImageRef image = CGImageSourceCreateImageAtIndex(_incrementalSource, currentlyDecodedIndex, NULL);
        CGImageRef decodedImage = OLDecodedCGImageFromCGImage(image);
        [self.images addObject:[UIImage imageWithCGImage:decodedImage]];
        
        free(oldDelayArray);
        CGImageRelease(image);
        CGImageRelease(decodedImage);
    }
    if (final) {
        CFRelease(_incrementalSource);
        _incrementalSource = nil;
    }
}

- (BOOL)isPartial
{
    return _incrementalSource != nil;
}

@end
