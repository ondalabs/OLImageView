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

//Define FLT_EPSILON because, reasons.
//Actually, I don't know why but it seems under certain circumstances it is not defined
#ifndef FLT_EPSILON
#define FLT_EPSILON __FLT_EPSILON__
#endif

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

inline static NSString *retinaSuffixForFilePath(NSString *path)
{
    NSUInteger suffixLength = 3;
    
    if (path.length < suffixLength) {
        return nil;
    }
    
    NSString *strippedPath = [path stringByDeletingPathExtension];
    
    NSRange suffixRange = NSMakeRange(strippedPath.length - suffixLength, suffixLength);
    return [strippedPath substringWithRange:suffixRange];
}

inline static CGFloat retinaScaleForFilePath(NSString *path)
{
    NSString *suffix = retinaSuffixForFilePath(path);
    
    if ([suffix isEqualToString:@"@3x"]) {
        return 3.0f;
    }
    if ([suffix isEqualToString:@"@2x"]) {
        return 2.0f;
    }
    return 1.0f;
}

inline static BOOL isRetinaFilePath(NSString *path)
{
    CGFloat scale = retinaScaleForFilePath(path);
    return scale > 1.0;
}


@interface OLImageSourceArray : NSArray

@property (nonatomic, readonly) CGImageSourceRef imageSource;

- (void)updateCount;

+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource;
+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource scale:(CGFloat)scale;

@end

@interface OLImage ()

@property (nonatomic, readwrite) NSTimeInterval *frameDurations;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;
@property (nonatomic, readwrite) CGImageSourceRef incrementalSource;
@property (nonatomic, readwrite) OLImageSourceArray *imageSourceArray;

@end

@implementation OLImage

@synthesize images;

#pragma mark - Class Methods

+ (id)imageNamed:(NSString *)name
{
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
    
    // If there isn't any path extension, we try to append the appropriate one, giving priority to *.gif
    if ([path pathExtension].length == 0) {
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathExtension:@"gif"]]) {
            path = [path stringByAppendingPathExtension:@"gif"];
        }
        else if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathExtension:@"png"]]) {
            path = [path stringByAppendingPathExtension:@"png"];
        }
    }
    
    // If no retina suffix present, we try to append the appropriate one
    if (!isRetinaFilePath(path)) {
        
        CGFloat scale = [UIScreen mainScreen].scale;
        
        if ([[UIScreen mainScreen] respondsToSelector:@selector(nativeScale)]) {
            scale = [UIScreen mainScreen].nativeScale; //This property returns @3x
        }
        
        NSString *suffix = [NSString stringWithFormat:@"@%gx", scale];
        
        NSMutableString *retinaPath = [path mutableCopy];
        
        NSUInteger idx = path.length-([path pathExtension].length+1);
        [retinaPath insertString:suffix atIndex:idx];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:retinaPath]) {
            path = retinaPath;
        }
    }
    
    return [self imageWithContentsOfFile:path];
}

+ (id)imageWithContentsOfFile:(NSString *)path
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return nil;
    }
    
    return [self imageWithData:[NSData dataWithContentsOfFile:path]
                         scale:retinaScaleForFilePath(path)];
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
                        scale:retinaScaleForFilePath(path)];
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
    
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    
    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyProperties(imageSource, NULL));
    NSDictionary *gifProperties = [imageProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
    
    self.frameDurations = (NSTimeInterval *)malloc(numberOfFrames  * sizeof(NSTimeInterval));
    self.loopCount = [gifProperties[(NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    for (NSUInteger i = 0; i < numberOfFrames; ++i) {
        NSTimeInterval frameDuration = CGImageSourceGetGifFrameDelay(imageSource, i);
        self.frameDurations[i] = frameDuration;
        self.totalDuration += frameDuration;
    }
    self.imageSourceArray = [OLImageSourceArray arrayWithImageSource:imageSource scale:scale];
    
    return self;
}

#pragma mark - Compatibility methods

- (NSArray *)images
{
    return self.imageSourceArray;
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

@implementation OLImage (IncrementalData)

//Snippet from AFNetworking
static inline CGImageRef OLCreateDecodedCGImageFromCGImage(CGImageRef imageRef)
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
    CGImageSourceRef incrementalSource = CGImageSourceCreateIncremental(NULL);
    image.imageSourceArray = [OLImageSourceArray arrayWithImageSource:incrementalSource];
    image.incrementalSource = incrementalSource;
    image.totalDuration = 0;
    image.frameDurations = calloc(1, sizeof(NSTimeInterval));
    
    CFRelease(incrementalSource);
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
    

    CGImageSourceUpdateData(_incrementalSource, (__bridge CFDataRef)([data copy]), final);
    [self.imageSourceArray updateCount];
    [self updateDurations];

    if (final) {
        _incrementalSource = NULL;
    }
}

- (void)updateDurations
{
    NSUInteger count = self.imageSourceArray.count;
    NSTimeInterval totalDuration = 0;
    NSTimeInterval *durations = calloc(count, sizeof(NSTimeInterval));
    for (int i = 0; i < count; i++) {
        NSTimeInterval delay = CGImageSourceGetGifFrameDelay(_incrementalSource, i);
        durations[i] = delay;
        totalDuration += delay;
    }
    
    free(_frameDurations);
    _frameDurations = durations;
    self.totalDuration = totalDuration;
}

- (BOOL)isPartial
{
    return _incrementalSource != nil;
}

@end

@interface OLImageSourceArray ()

@property (nonatomic, readonly) NSCache *frameCache;
@property (nonatomic) NSUInteger frameCount;
@property (nonatomic, readonly) CGFloat scale;

@end

@implementation OLImageSourceArray

+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource
{
    return [self arrayWithImageSource:imageSource scale:1.0f];
}

+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource scale:(CGFloat)scale
{
    if (!imageSource) {
        return nil;
    }
    return [[self alloc] initWithImageSource:imageSource scale:scale];
}

- (instancetype)initWithImageSource:(CGImageSourceRef)imageSource scale:(CGFloat)scale
{
    self = [super init];
    if (self) {
        CFRetain(imageSource);
        _imageSource = imageSource;
        _frameCache = [NSCache new];
        [_frameCache setCountLimit:10];
        _frameCount = 0;
        _scale = scale;
        [self updateCount];
    }
    return self;
}

- (NSUInteger)count
{
    return self.frameCount;
}

- (id)objectAtIndex:(NSUInteger)idx
{
    id object = [self.frameCache objectForKey:@(idx)];
    if (!object) {
        object = [self _objectAtIndex:idx];
    }
    return object;
}

- (BOOL)containsObject:(id)anObject
{
    return [[(id)self.frameCache allObjects] containsObject:anObject];
}

- (id)_objectAtIndex:(NSUInteger)idx
{
    CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(self.imageSource, idx, NULL);
    UIImage *image = [UIImage imageWithCGImage:frameImageRef scale:self.scale orientation:UIImageOrientationUp];
    CGImageRelease(frameImageRef);
    if (image) {
        [self.frameCache setObject:image forKey:@(idx)];
    }
    return image;
}

- (void)updateCount
{
    NSInteger count = CGImageSourceGetCount(self.imageSource);
    if (CGImageSourceGetStatus(self.imageSource) != kCGImageStatusComplete) {
        count -=2;
    }
    self.frameCount = MAX(0, count);
    NSUInteger cacheLimit = self.frameCache.countLimit;
    if (self.frameCount > 0) {
        cacheLimit = MIN(self.frameCount, 10);
    }
    [self.frameCache setCountLimit:cacheLimit];
}

- (void)dealloc
{
    CFRelease(_imageSource);
}

@end
