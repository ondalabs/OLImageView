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

@interface OLImage ()

@property (nonatomic, readwrite) NSMutableArray *images;
@property (nonatomic, readwrite) NSTimeInterval *frameDurations;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;

@end

@implementation OLImage

@synthesize images;

#pragma mark - Class Methods

+ (NSString *)getResourceFilePath:(NSString *)path withSuffix:(NSString *)suffix
{
    if (!path.length) {
        return nil;
    }
    
    NSString *extension = [path pathExtension];
    NSString *pathWithoutExtension = [path stringByDeletingPathExtension];
    NSString *suffixedPath = pathWithoutExtension;
    NSString *name = [pathWithoutExtension lastPathComponent];
    NSString *resourcePath = nil;
    
    if (suffix && [name rangeOfString:suffix options:NSCaseInsensitiveSearch].location == NSNotFound) {
        suffixedPath = [suffixedPath stringByAppendingString:suffix];
    }
    
    if ((resourcePath = [[NSBundle mainBundle] pathForResource:suffixedPath ofType:extension])) {
        if ([resourcePath rangeOfString:suffixedPath options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return resourcePath;
        }
    }
    
    const NSArray * const kSupportedExtensions = @[@"gif", @"png", @"jpg", @"jpeg", @"tiff", @"tif", @"bmp", @"bmpf", @"ico", @"cur", @"xbm"];
    if (!extension.length || [kSupportedExtensions indexOfObject:[extension lowercaseString]] == NSNotFound) {
        for (NSString *supportedExtension in kSupportedExtensions) {
            if ((resourcePath = [[NSBundle mainBundle] pathForResource:suffixedPath ofType:supportedExtension])) {
                if ([resourcePath rangeOfString:suffixedPath options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    return resourcePath;
                }
            }
        }
    }
    return nil;
}

+ (UIImage *)imageNamed:(NSString *)name
{
    BOOL isiPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    BOOL isRetina = [[UIScreen mainScreen] scale] > 1;
    NSString *path = name;
    
    if (isiPad) {
        if (isRetina && (path = [self getResourceFilePath:name withSuffix:@"@2x~ipad"])) {
            return [OLImage imageWithData:[NSData dataWithContentsOfFile:path] scale:2];
        }
        if ((path = [self getResourceFilePath:name withSuffix:@"~ipad"])) {
            return [OLImage imageWithData:[NSData dataWithContentsOfFile:path] scale:1];
        }
    }
    if (isRetina && (path = [self getResourceFilePath:name withSuffix:@"@2x"])) {
        return [OLImage imageWithData:[NSData dataWithContentsOfFile:path] scale:2];
    }
    
    path = [self getResourceFilePath:name withSuffix:nil];
    return [OLImage imageWithData:[NSData dataWithContentsOfFile:path] scale:1];
}

+ (UIImage *)imageWithContentsOfFile:(NSString *)path
{
    return [[self alloc] initWithContentsOfFile:path];
}

+ (id)imageWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

+ (id)imageWithData:(NSData *)data scale:(CGFloat)scale
{
    return [[self alloc] initWithData:data scale:scale];
}

#pragma mark - Instance Methods

- (id)initWithContentsOfFile:(NSString *)path
{
    NSRange retinaSuffixRange = [[path lastPathComponent] rangeOfString:@"@2x" options:NSCaseInsensitiveSearch];
    BOOL isRetinaPath = retinaSuffixRange.length && retinaSuffixRange.location != NSNotFound;
    return [self initWithData:[NSData dataWithContentsOfFile:path]
                        scale:isRetinaPath ? 2 : 1];
}

- (id)initWithData:(NSData *)data
{
    return [self initWithData:data scale:1];
}

- (id)initWithData:(NSData *)data scale:(CGFloat)scale
{
    if (!data) {
        return nil;
    }
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)(data), NULL);
    
    if (!imageSource) {
        if (scale > 1 && [[self superclass] instancesRespondToSelector:@selector(initWithData:scale:)]) {
            return [super initWithData:data scale:scale];
        } else {
            return [super initWithData:data];
        }
    }
    
    NSUInteger numberOfFrames = CGImageSourceGetCount(imageSource);
    
    if (numberOfFrames == 1 || !UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF)) {
        CFRelease(imageSource);
        if (scale > 1 && [[self superclass] instancesRespondToSelector:@selector(initWithData:scale:)]) {
            return [super initWithData:data scale:scale];
        } else {
            return [super initWithData:data];
        }
    }
    
    self = [super init];
    
    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyProperties(imageSource, NULL));
    NSDictionary *gifProperties = [imageProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
    
    self.frameDurations = (NSTimeInterval *)malloc(numberOfFrames  * sizeof(NSTimeInterval));
    self.loopCount = [gifProperties[(NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    self.images = [NSMutableArray arrayWithCapacity:numberOfFrames];
    
    // Load First Frame
    CGImageRef firstImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    [self.images addObject:[UIImage imageWithCGImage:firstImage scale:scale orientation:UIImageOrientationUp]];
    CFRelease(firstImage);
    
    NSTimeInterval firstFrameDuration = CGImageSourceGetGifFrameDelay(imageSource, 0);
    self.frameDurations[0] = firstFrameDuration;
    self.totalDuration = firstFrameDuration;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 1; i < numberOfFrames; ++i) {
            NSTimeInterval frameDuration = CGImageSourceGetGifFrameDelay(imageSource, i);
            self.frameDurations[i] = frameDuration;
            self.totalDuration += frameDuration;

            CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(imageSource, i, NULL);
            [self.images addObject:[UIImage imageWithCGImage:frameImageRef scale:scale orientation:UIImageOrientationUp]];
            CFRelease(frameImageRef);
        }
        CFRelease(imageSource);
    });
    
    return self;
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
