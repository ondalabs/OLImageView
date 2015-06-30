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

@interface OLImageView () {
    struct {
        unsigned int didLoop : 1;
        unsigned int shouldStartAnimating : 1;
    } _delegateFlags;
}

@property (nonatomic, strong) OLImage *animatedImage;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) NSTimeInterval accumulator;
@property (nonatomic) NSUInteger currentFrameIndex;
@property (nonatomic) NSUInteger loopCountdown;

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
    }
    return self;
}

- (CADisplayLink *)displayLink
{
    if (self.superview) {
        if (!_displayLink && self.animatedImage && [self delegateShouldStartAnimating]) {
            _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(changeKeyframe:)];
            [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.runLoopMode];
        }
    } else {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    return _displayLink;
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
        
        [self startAnimating];
    }
}

- (void)setDelegate:(id<OLImageViewDelegate>)delegate
{
    if (delegate == _delegate) {
        return;
    }
    _delegate = delegate;
    _delegateFlags.didLoop = [delegate respondsToSelector:@selector(imageViewDidLoop:)];
    _delegateFlags.shouldStartAnimating = [delegate respondsToSelector:@selector(imageViewShouldStartAnimating:)];
}

- (void)setImage:(UIImage *)image
{
    if (image == self.image) {
        return;
    }
    
    [self stopAnimating];
    
    self.currentFrameIndex = 0;
    self.loopCountdown = 0;
    self.accumulator = 0;
    
    if ([image isKindOfClass:[OLImage class]] && image.images) {
        [super setImage:nil];
        self.animatedImage = (OLImage *)image;
        self.loopCountdown = self.animatedImage.loopCount ?: NSUIntegerMax;
        [self startAnimating];
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
        self.layer.contentsScale = 1;
    } else {
        self.layer.contentsScale = animatedImage.scale;
    }
}

#define OLCaseContentMode(aCase) \
case UIViewContentMode##aCase: \
contentsGravity = kCAGravity##aCase; \
break

- (void)setContentMode:(UIViewContentMode)contentMode
{
    NSString *contentsGravity;
    switch (contentMode) {
            OLCaseContentMode(Bottom);
            OLCaseContentMode(BottomLeft);
            OLCaseContentMode(BottomRight);
            OLCaseContentMode(Top);
            OLCaseContentMode(TopLeft);
            OLCaseContentMode(TopRight);
            OLCaseContentMode(Center);
            OLCaseContentMode(Right);
            OLCaseContentMode(Left);
        case UIViewContentModeScaleAspectFill:
            contentsGravity = kCAGravityResizeAspectFill;
            break;
        case UIViewContentModeScaleAspectFit:
            contentsGravity = kCAGravityResizeAspect;
            break;
        case UIViewContentModeScaleToFill:
        case UIViewContentModeRedraw:
            contentsGravity = kCAGravityResize;
            break;
    }
    self.layer.contentsGravity = contentsGravity;
    [super setContentMode:contentMode];
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
    
    self.displayLink.paused = YES;
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
    
    self.displayLink.paused = ! [self delegateShouldStartAnimating];
}

- (void)changeKeyframe:(CADisplayLink *)displayLink
{
    if (self.currentFrameIndex >= [self.animatedImage.images count] && [self.animatedImage isPartial]) {
        return;
    }
    self.accumulator += fmin(displayLink.duration, kMaxTimeStep);
    
    while (self.accumulator >= self.animatedImage.frameDurations[self.currentFrameIndex]) {
        self.accumulator -= self.animatedImage.frameDurations[self.currentFrameIndex];
        if (++self.currentFrameIndex >= [self.animatedImage.images count] && ![self.animatedImage isPartial]) {
            if (--self.loopCountdown == 0) {
                [self stopAnimating];
                return;
            }
            self.currentFrameIndex = 0;
            [self delegateDidLoop];
        }
        self.currentFrameIndex = MIN(self.currentFrameIndex, [self.animatedImage.images count] - 1);
        [self.layer setNeedsDisplay];
    }
}

- (void)displayLayer:(CALayer *)layer
{
    if (!self.animatedImage || [self.animatedImage.images count] == 0) {
        return;
    }
    layer.contents = (__bridge id)([[self.animatedImage.images objectAtIndex:self.currentFrameIndex] CGImage]);
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    [super setBackgroundColor:backgroundColor];
    self.layer.backgroundColor = [backgroundColor CGColor];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
        [self startAnimating];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.window) {
                [self stopAnimating];
            }
        });
    }
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    if (self.superview) {
        //Has a superview, make sure it has a displayLink
        [self displayLink];
    } else {
        //Doesn't have superview, let's check later if we need to remove the displayLink
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayLink];
        });
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

- (CGSize)sizeThatFits:(CGSize)size
{
    return self.image.size;
}

#pragma mark - delegation
- (BOOL)delegateShouldStartAnimating {
    
    if (self.delegate && _delegateFlags.shouldStartAnimating) {
        return [self.delegate imageViewShouldStartAnimating:self];
    } else {
        return YES;
    }
}

- (void)delegateDidLoop {
    
    if (self.delegate && _delegateFlags.didLoop) {
        [self.delegate imageViewDidLoop:self];
    }
}
@end
