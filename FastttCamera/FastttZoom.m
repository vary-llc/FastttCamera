//
//  FastttZoom.m
//  FastttCamera
//
//  Created by Laura Skelton on 3/5/15.
//
//

#import "FastttZoom.h"
#import "IFTTTDeviceOrientation.h"

CGFloat const kZoomCircleSize = 60.f;

@interface FastttZoom ()
{
    UILabel *zoomLabel;
    IFTTTDeviceOrientation *deviceOrientation;
}
@property (nonatomic, strong) UIView *view;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGestureRecognizer;
@property (nonatomic, assign) CGFloat lastScale;

@end

@implementation FastttZoom

+ (instancetype)fastttZoomWithView:(UIView *)view gestureDelegate:(id <UIGestureRecognizerDelegate>)gestureDelegate
{
    if (!view) {
        return nil;
    }
    
    FastttZoom *fastZoom = [[self alloc] init];
    
    fastZoom.view = view;
    
    fastZoom.maxScale = 1.f;
    
    fastZoom.currentScale = 1.f;
    
    fastZoom.gestureDelegate = gestureDelegate;
    
    fastZoom.detectsPinch = YES;
    
    return fastZoom;
}

- (void)dealloc
{
    self.delegate = nil;
    
    [self _teardownPinchZoomRecognizer];
}

- (void)setDetectsPinch:(BOOL)detectsPinch
{
    if (_detectsPinch != detectsPinch) {
        _detectsPinch = detectsPinch;
        if (_detectsPinch) {
            [self _setupPinchZoomRecognizer];
        } else {
            [self _teardownPinchZoomRecognizer];
        }
    }
}

- (void)showZoomViewWithScale:(CGFloat)zoomScale
{
    // TODO: draw a line with a circle and plus minus at the bottom similar to system camera zoom indicator
    
    // CGFloat zoomPercent = [self _zoomPercentFromZoomScale:self.currentScale];
    self.currentScale = zoomScale;
    return;
    
    if (!deviceOrientation) {
        deviceOrientation = [IFTTTDeviceOrientation new];
    }
    
    if (!zoomLabel) {
        zoomLabel = [UILabel new];
        zoomLabel.frame = CGRectMake(0, 0, kZoomCircleSize, kZoomCircleSize);
        zoomLabel.layer.borderColor = [UIColor whiteColor].CGColor;
        zoomLabel.layer.borderWidth = 1.f;
        zoomLabel.layer.cornerRadius = kZoomCircleSize / 2;
        zoomLabel.clipsToBounds = YES;
        zoomLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.1];
        zoomLabel.textColor = [UIColor whiteColor];
        zoomLabel.textAlignment = NSTextAlignmentCenter;
        zoomLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    }
    
    zoomLabel.center = self.view.center;

    if (![self.view.subviews containsObject: zoomLabel]){
        [self.view addSubview: zoomLabel];
    }else{
        [self.view bringSubviewToFront: zoomLabel];
    }

    zoomLabel.text = [NSString stringWithFormat:@"%.1f�", zoomScale];
    zoomLabel.alpha = 0.f;
    
    switch (deviceOrientation.orientation) {
        case UIDeviceOrientationPortrait:
        zoomLabel.transform = CGAffineTransformIdentity;
        break;
        case UIDeviceOrientationPortraitUpsideDown:
        zoomLabel.transform = CGAffineTransformMakeRotation(180.0 * M_PI / 180.0);
        break;
        case UIDeviceOrientationLandscapeLeft:
        zoomLabel.transform = CGAffineTransformMakeRotation(90.0 * M_PI / 180.0);
        break;
        case UIDeviceOrientationLandscapeRight:
        zoomLabel.transform = CGAffineTransformMakeRotation(270.0 * M_PI / 180.0);
        break;
        default:
        break;
    }
    
    [UIView animateWithDuration:0.3f
                          delay:0.f
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         zoomLabel.alpha = 1.f;
                         
                     } completion:^(BOOL finished){
                         [UIView animateWithDuration:0.2f
                                               delay:0.5f
                                             options:UIViewAnimationOptionCurveEaseIn
                                          animations:^{
                                              zoomLabel.alpha = 0.f;
                                          } completion:^(BOOL finishedFadeout){
                                              //[zoomLabel removeFromSuperview];
                                          }];
                     }];
}

- (void)resetZoom
{
    // TODO: hide and reset zoom view.
    
    self.currentScale = 1.f;
    self.maxScale = 1.f;
}

#pragma mark - Pinch to Zoom

- (void)_setupPinchZoomRecognizer
{
    _pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePinchZoom:)];
    [self.view addGestureRecognizer:self.pinchGestureRecognizer];
    
    self.pinchGestureRecognizer.cancelsTouchesInView = YES;
    self.pinchGestureRecognizer.delegate = self.gestureDelegate;
}

- (void)_teardownPinchZoomRecognizer
{
    if ([self.view.gestureRecognizers containsObject:self.pinchGestureRecognizer]) {
        [self.view removeGestureRecognizer:self.pinchGestureRecognizer];
    }
    
    self.pinchGestureRecognizer = nil;
}

- (void)_handlePinchZoom:(UIPinchGestureRecognizer *)recognizer
{
    CGFloat newScale = recognizer.scale * self.currentScale;
    
    if (newScale > self.maxScale) {
        newScale = self.maxScale;
    }
        
    if (newScale < 1.f) {
        newScale = 1.f;
    }
    
    if ([self.delegate handlePinchZoomWithScale:newScale]) {
        self.lastScale = newScale;
        [self showZoomViewWithScale:self.lastScale];
    }
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        self.currentScale = self.lastScale;
    }
}

- (CGFloat)_zoomPercentFromZoomScale:(CGFloat)zoomScale
{
    // Calculate a number between 0 and 1 from a zoomScale which ranges from 1 to self.maxScale
    return (zoomScale - 1.f) / (self.maxScale - 1.f);
}

@end
