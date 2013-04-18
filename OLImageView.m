//
//  OLImageView.m
//  OLImageViewDemo
//
//  Created by Diego Torres on 9/5/12.
//  Copyright (c) 2012 Onda Labs. All rights reserved.
//

#import "OLImageView.h"
#import "OLImage.h"
#import <QuartzCore/QuartzCore.h>

@interface OLImageView ()

@property (nonatomic, strong) OLImage *animatedImage;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) NSTimeInterval accumulator;
@property (nonatomic) NSUInteger currentFrameIndex;
@property (nonatomic) NSUInteger loopCountdown;
@property (nonatomic) BOOL started;
@end

@implementation OLImageView

const NSTimeInterval kMaxTimeStep = 1; // note: To avoid spiral-o-death

@synthesize runLoopMode = _runLoopMode;
@synthesize displayLink = _displayLink;

- (id)init
{
    self = [super init];
    if (self) {
        self.currentFrameIndex = 0;
		self.autoplay = YES;
    }
    return self;
}

- (void)dealloc
{
    self.displayLink = nil;
}

- (void)setDisplayLink:(CADisplayLink *)displayLink
{
    if (displayLink != _displayLink) {
        [_displayLink invalidate];
        _displayLink = displayLink;
    }
}

- (NSString *)runLoopMode
{
    return _runLoopMode ?: NSDefaultRunLoopMode;
}

- (void)setRunLoopMode:(NSString *)runLoopMode
{
    if (runLoopMode != _runLoopMode) {
        [self stopAnimating];
        
        NSRunLoop *runloop = [NSRunLoop mainRunLoop];
        [self.displayLink removeFromRunLoop:runloop forMode:_runLoopMode];
        [self.displayLink addToRunLoop:runloop forMode:runLoopMode];
        
        _runLoopMode = runLoopMode;
        
        [self startAutoplaying];
    }
}

- (void)setImage:(UIImage *)image
{
    [self stopAnimating];
    
    self.currentFrameIndex = 0;
    self.loopCountdown = 0;
    self.accumulator = 0;
    
    if ([image isKindOfClass:[OLImage class]] && image.images) {
        self.animatedImage = (OLImage *)image;
        self.loopCountdown = self.animatedImage.loopCount ?: NSUIntegerMax;
		[self startAutoplaying];
    } else {
        self.animatedImage = nil;
        [super setImage:image];
    }
    [self.layer setNeedsDisplay];
}

- (void)setAnimatedImage:(OLImage *)animatedImage
{
    _animatedImage = animatedImage;
    if (animatedImage == nil) {
        self.layer.contents = nil;
    }
}

-(void)setAutoplay:(BOOL)autoplay {
	
	_autoplay = autoplay;
	if(_autoplay) {
		[self stopAnimating];
		self.currentFrameIndex = 0;
		[self startAutoplaying];
	}
}

- (BOOL)isAnimating
{
    return [super isAnimating] || (self.displayLink && !self.displayLink.isPaused);
}

- (void)stopAnimating
{
    if (!self.animatedImage) {
        [super stopAnimating];
        return;
    }
    
    self.loopCountdown = 0;
    self.currentFrameIndex = 0;
    self.displayLink.paused = YES;
	
	[[NSNotificationCenter defaultCenter]postNotificationName:kOLImageViewGIFAnimationEnded object:self];
}

- (void)startAnimating
{
    if (!self.animatedImage) {
        [super startAnimating];
        return;
    }
    
    if (self.isAnimating) {
        return;
    }
    
    self.loopCountdown = self.animatedImage.loopCount ?: NSUIntegerMax;
    
    if (!self.displayLink) {
		self.started = YES;
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(changeKeyframe:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.runLoopMode];
    }
    
    self.displayLink.paused = NO;
	[[NSNotificationCenter defaultCenter]postNotificationName:kOLImageViewGIFAnimationStarted object:self];
}

-(void)startAutoplaying {
	
	if(self.autoplay || self.started)
		[self startAnimating];
}

- (void)changeKeyframe:(CADisplayLink *)displayLink
{
    self.accumulator += fmin(displayLink.duration, kMaxTimeStep);
    
    while (self.accumulator >= self.animatedImage.frameDurations[self.currentFrameIndex]) {
        self.accumulator -= self.animatedImage.frameDurations[self.currentFrameIndex];
        if (++self.currentFrameIndex >= [self.animatedImage.images count]) {
            if (--self.loopCountdown == 0) {
                [self stopAnimating];
                return;
            }
            self.currentFrameIndex = 0;
			[[NSNotificationCenter defaultCenter]postNotificationName:kOLImageViewGIFAnimationLooped object:self];
        }
        [self.layer setNeedsDisplay];
    }
}

- (void)displayLayer:(CALayer *)layer
{
    if (!self.animatedImage) {
        return;
    }
    layer.contents = (__bridge id)([[self.animatedImage.images objectAtIndex:self.currentFrameIndex] CGImage]);
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
		[self startAutoplaying];
    } else {
        [self stopAnimating];
    }
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (!self.animatedImage) {
        [super setHighlighted:highlighted];
    }
}

- (UIImage *)image
{
    return self.animatedImage ?: [super image];
}

@end
