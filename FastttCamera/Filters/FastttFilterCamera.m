//
//  FastttFilterCamera.m
//  FastttCamera
//
//  Created by Laura Skelton on 2/5/15.
//  Copyright (c) 2015 IFTTT. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <GPUImage/GPUImage.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "FastttFilterCamera.h"
#import "IFTTTDeviceOrientation.h"
#import "UIImage+FastttCamera.h"
#import "AVCaptureDevice+FastttCamera.h"
#import "FastttFocus.h"
#import "FastttZoom.h"
#import "FastttFilter.h"
#import "FastttCapturedImage+Process.h"

@interface FastttFilterCamera () <FastttFocusDelegate, FastttZoomDelegate, GPUImageVideoCameraDelegate>

@property (nonatomic, strong) IFTTTDeviceOrientation *deviceOrientation;
@property (nonatomic, strong) FastttFocus *fastFocus;
@property (nonatomic, strong) FastttZoom *fastZoom;
@property (nonatomic, strong) GPUImageStillCamera *stillCamera;
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
@property (nonatomic, strong) FastttFilter *fastFilter;
@property (nonatomic, strong) GPUImageView *previewView;
@property (nonatomic, strong) GPUImageCropFilter *cropFilter;
@property (nonatomic, assign) BOOL deviceAuthorized;
@property (nonatomic, assign) BOOL isCapturingImage;
@property (nonatomic, assign) BOOL isTakingPhotoSilent;
@property (nonatomic, strong) NSURL *movieURL;
@property (nonatomic, assign) CGFloat currentZoomScale;
@property (nonatomic, strong) NSMutableDictionary *currentMetadata;

@end

@implementation FastttFilterCamera

@synthesize delegate = _delegate,
returnsRotatedPreview = _returnsRotatedPreview,
showsFocusView = _showsFocusView,
maxScaledDimension = _maxScaledDimension,
normalizesImageOrientations = _normalizesImageOrientations,
cropsImageToVisibleAspectRatio = _cropsImageToVisibleAspectRatio,
interfaceRotatesWithOrientation = _interfaceRotatesWithOrientation,
fixedInterfaceOrientation = _fixedInterfaceOrientation,
handlesTapFocus = _handlesTapFocus,
handlesZoom = _handlesZoom,
maxZoomFactor = _maxZoomFactor,
showsZoomView = _showsZoomView,
gestureView = _gestureView,
gestureDelegate = _gestureDelegate,
scalesImage = _scalesImage,
cameraDevice = _cameraDevice,
cameraFlashMode = _cameraFlashMode,
cameraTorchMode = _cameraTorchMode,
normalizesVideoOrientation = _normalizesVideoOrientation,
cropsVideoToVisibleAspectRatio = _cropsVideoToVisibleAspectRatio;


- (instancetype)init
{
    if ((self = [super init])) {
        
        [self _setupCaptureSession];
        
        _handlesTapFocus = YES;
        _showsFocusView = YES;
        _handlesZoom = YES;
        _maxZoomFactor = 1.f;
        _showsZoomView = YES;
        _cropsImageToVisibleAspectRatio = YES;
        _cropsVideoToVisibleAspectRatio = YES;
        _scalesImage = YES;
        _maxScaledDimension = 0.f;
        _normalizesImageOrientations = YES;
        _normalizesVideoOrientation = YES;
        _returnsRotatedPreview = YES;
        _interfaceRotatesWithOrientation = YES;
        _fixedInterfaceOrientation = UIDeviceOrientationPortrait;
        _cameraDevice = FastttCameraDeviceRear;
        _cameraFlashMode = FastttCameraFlashModeOff;
        _cameraTorchMode = FastttCameraTorchModeOff;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    
    return self;
}

+ (instancetype)cameraWithFilterImage:(UIImage *)filterImage
{
    FastttFilterCamera *fastCamera = [[FastttFilterCamera alloc] init];
    
    fastCamera.fastFilter = [FastttFilter filterWithLookupImage:filterImage];
    
    return fastCamera;
}

- (void)dealloc
{
    _fastFocus = nil;
    _fastFilter = nil;
    _fastZoom = nil;
    
    [self _teardownCaptureSession];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View Events

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self _insertPreviewLayer];
    
    UIView *viewForGestures = self.view;
    
    if (self.gestureView) {
        viewForGestures = self.gestureView;
    }
    
    _fastFocus = [FastttFocus fastttFocusWithView:viewForGestures gestureDelegate:self.gestureDelegate];
    self.fastFocus.delegate = self;
    
    if (!self.handlesTapFocus) {
        self.fastFocus.detectsTaps = NO;
    }
    
    _fastZoom = [FastttZoom fastttZoomWithView:viewForGestures gestureDelegate:self.gestureDelegate];
    self.fastZoom.delegate = self;
    
    if (!self.handlesZoom) {
        self.fastZoom.detectsPinch = NO;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self startRunning];
    
    [self _insertPreviewLayer];
    
    [self _setPreviewVideoOrientation];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self stopRunning];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    _previewView.frame = self.view.bounds;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self _setupCaptureSession];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (self.isViewLoaded && self.view.window) {
        [self startRunning];
        [self _insertPreviewLayer];
        [self _setPreviewVideoOrientation];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self stopRunning];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self _teardownCaptureSession];
}

#pragma mark - Autorotation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self _setPreviewVideoOrientation];
}

#pragma mark - Taking a Photo

- (BOOL)isReadyToCapturePhoto
{
    return !self.isCapturingImage;
}

- (void)takePicture
{
    if (!_deviceAuthorized) {
        return;
    }
    
    [self _takePhoto];
}

- (void)takePictureSilent
{
    if (!_deviceAuthorized) {
        return;
    }
    
    [self _takePhotoSilent];
}

- (void)cancelImageProcessing
{
    if (_isCapturingImage) {
        _isCapturingImage = NO;
    }
}

#pragma mark - Processing a Photo

- (void)processImage:(UIImage *)image withMaxDimension:(CGFloat)maxDimension
{
    [self _processImage:image withCropRect:CGRectNull maxDimension:maxDimension fromCamera:NO needsPreviewRotation:NO previewOrientation:UIDeviceOrientationUnknown];
}

- (void)processImage:(UIImage *)image withCropRect:(CGRect)cropRect
{
    [self _processImage:image withCropRect:cropRect maxDimension:0.f fromCamera:NO needsPreviewRotation:NO previewOrientation:UIDeviceOrientationUnknown];
}

- (void)processImage:(UIImage *)image withCropRect:(CGRect)cropRect maxDimension:(CGFloat)maxDimension
{
    [self _processImage:image withCropRect:cropRect maxDimension:maxDimension fromCamera:NO needsPreviewRotation:NO previewOrientation:UIDeviceOrientationUnknown];
}

#pragma mark - Camera State

+ (BOOL)isPointFocusAvailableForCameraDevice:(FastttCameraDevice)cameraDevice
{
    return [AVCaptureDevice isPointFocusAvailableForCameraDevice:cameraDevice];
}

- (BOOL)focusAtPoint:(CGPoint)touchPoint
{
    CGPoint pointOfInterest = [self _focusPointOfInterestForTouchPoint:touchPoint];
    
    return [self _focusAtPointOfInterest:pointOfInterest];
}

- (BOOL)zoomToScale:(CGFloat)scale
{
    _currentZoomScale = scale;
    return [[self _currentCameraDevice] zoomToScale:scale];
}

- (BOOL)isFlashAvailableForCurrentDevice
{
    AVCaptureDevice *device = [self _currentCameraDevice];
    
    if ([device isFlashModeSupported:AVCaptureFlashModeOn]) {
        return YES;
    }
    
    return NO;
}

+ (BOOL)isFlashAvailableForCameraDevice:(FastttCameraDevice)cameraDevice
{
    return [AVCaptureDevice isFlashAvailableForCameraDevice:cameraDevice];
}

- (BOOL)isTorchAvailableForCurrentDevice
{
    AVCaptureDevice *device = [self _currentCameraDevice];
    
    if ([device isTorchModeSupported:AVCaptureTorchModeOn]) {
        return YES;
    }
    
    return NO;
}

+ (BOOL)isTorchAvailableForCameraDevice:(FastttCameraDevice)cameraDevice
{
    return [AVCaptureDevice isTorchAvailableForCameraDevice:cameraDevice];
}

+ (BOOL)isCameraDeviceAvailable:(FastttCameraDevice)cameraDevice
{
    return ([AVCaptureDevice cameraDevice:cameraDevice] != nil);
}

- (void)setCameraDevice:(FastttCameraDevice)cameraDevice
{
    AVCaptureDevice *device = [AVCaptureDevice cameraDevice:cameraDevice];
    
    if (!device) {
        return;
    }
    
    if (_cameraDevice != cameraDevice) {
        _cameraDevice = cameraDevice;
    }
    
    if (_stillCamera.cameraPosition != [AVCaptureDevice positionForCameraDevice:cameraDevice]) {
        [_stillCamera rotateCamera];
    }
    
    [self setCameraFlashMode:_cameraFlashMode];
    
    [self _resetZoom];
}

- (void)setCameraFlashMode:(FastttCameraFlashMode)cameraFlashMode
{
    AVCaptureDevice *device = [self _currentCameraDevice];
    
    if ([AVCaptureDevice isFlashAvailableForCameraDevice:self.cameraDevice]) {
        _cameraFlashMode = cameraFlashMode;
        [device setCameraFlashMode:cameraFlashMode];
        return;
    }
    
    _cameraFlashMode = FastttCameraFlashModeOff;
}

- (void)setCameraTorchMode:(FastttCameraTorchMode)cameraTorchMode
{
    AVCaptureDevice *device = [self _currentCameraDevice];
    
    if ([AVCaptureDevice isTorchAvailableForCameraDevice:self.cameraDevice]) {
        _cameraTorchMode = cameraTorchMode;
        [device setCameraTorchMode:cameraTorchMode];
        return;
    }
    
    _cameraTorchMode = FastttCameraTorchModeOff;
}

#pragma mark - Filtering

- (FastttFilter *)fastFilter
{
    if (!_fastFilter) {
        _fastFilter = [FastttFilter plainFilter];
    }
    
    return _fastFilter;
}

- (void)setFilterImage:(UIImage *)filterImage
{
    _fastFilter = [FastttFilter filterWithLookupImage:filterImage];
    _filterImage = filterImage;
    [self _insertPreviewLayer];
}

#pragma mark - Capture Session Management

- (void)startRunning
{
    [_stillCamera startCameraCapture];
}

- (void)stopRunning
{
    [_stillCamera stopCameraCapture];
    
    if (_movieWriter) {
        [self stopRecordingVideo];
    }
}

- (void)_insertPreviewLayer
{
    if (!_deviceAuthorized) {
        return;
    }
    
    if (([_previewView superview] == self.view)
        && [_stillCamera.targets containsObject:self.fastFilter.filter]
        && [self.fastFilter.filter.targets containsObject:_previewView]) {
        return;
    }
    
    if (!_previewView) {
        _previewView = [[GPUImageView alloc] init];
        [self.view addSubview:_previewView];
        _previewView.frame = self.view.bounds;
        _previewView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    }
    
    [_stillCamera removeAllTargets];
    [self.fastFilter.filter removeAllTargets];
    
    [_stillCamera addTarget:self.fastFilter.filter];
    [self.fastFilter.filter addTarget:_previewView];
}

- (void)_removePreviewLayer
{
    [_stillCamera removeAllTargets];
    [self.fastFilter.filter removeAllTargets];
    
    [_previewView removeFromSuperview];
    _previewView = nil;
}

- (void)_setupCaptureSession
{
    if (_stillCamera) {
        return;
    }
    
#if !TARGET_IPHONE_SIMULATOR
    [self _checkDeviceAuthorizationWithCompletion:^(BOOL isAuthorized) {
        
        _deviceAuthorized = isAuthorized;
#else
        _deviceAuthorized = YES;
#endif
        if (_stillCamera) {
            return;
        }
        
        if (!_deviceAuthorized && [self.delegate respondsToSelector:@selector(userDeniedCameraPermissionsForCameraController:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate userDeniedCameraPermissionsForCameraController:self];
            });
        }
        
        if (_deviceAuthorized) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (_stillCamera) {
                    return;
                }
                
                AVCaptureDevice *device = [AVCaptureDevice cameraDevice:self.cameraDevice];
                
                if (!device) {
                    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                }
                
                AVCaptureDevicePosition position = [device position];
                
                _stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:position];
                _stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
                //_stillCamera.horizontallyMirrorFrontFacingCamera = YES;
                _stillCamera.delegate = self;
                
                switch (position) {
                    case AVCaptureDevicePositionBack:
                        _cameraDevice = FastttCameraDeviceRear;
                        break;
                        
                    case AVCaptureDevicePositionFront:
                        _cameraDevice = FastttCameraDeviceFront;
                        break;
                        
                    default:
                        break;
                }
                
                [self setCameraFlashMode:_cameraFlashMode];
                
                _deviceOrientation = [IFTTTDeviceOrientation new];
                
                if (self.isViewLoaded && self.view.window) {
                    [self _insertPreviewLayer];
                    [self startRunning];
                    [self _setPreviewVideoOrientation];
                    [self _resetZoom];
                }
                
            });
        }
#if !TARGET_IPHONE_SIMULATOR
    }];
#endif
}

- (void)_teardownCaptureSession
{
    if (!_stillCamera) {
        return;
    }
    
    _deviceOrientation = nil;
    
    [_stillCamera stopCameraCapture];
    
    [_stillCamera removeInputsAndOutputs];
    
    [self _removePreviewLayer];
    
    _stillCamera = nil;
}

#pragma mark - Capturing a Photo

- (void)_takePhoto
{
    if (self.isCapturingImage) {
        return;
    }
    self.isCapturingImage = YES;
    
    BOOL needsPreviewRotation = ![self.deviceOrientation deviceOrientationMatchesInterfaceOrientation];
    
#if TARGET_IPHONE_SIMULATOR
    UIImage *fakeImage = [UIImage fastttFakeTestImage];
    [self _processCameraPhoto:fakeImage needsPreviewRotation:needsPreviewRotation imageOrientation:UIImageOrientationUp previewOrientation:UIDeviceOrientationPortrait];
#else
    
    UIDeviceOrientation previewOrientation = [self _currentPreviewDeviceOrientation];
    
    UIImageOrientation outputImageOrientation = [self _outputImageOrientation];
    
    [_stillCamera capturePhotoAsImageProcessedUpToFilter:self.fastFilter.filter withOrientation:UIImageOrientationUp withCompletionHandler:^(UIImage *processedImage, NSError *error){
        self.currentMetadata = _stillCamera.currentCaptureMetadata.mutableCopy;
        
        if (self.isCapturingImage) {
            [self _processCameraPhoto:processedImage needsPreviewRotation:needsPreviewRotation imageOrientation:outputImageOrientation previewOrientation:previewOrientation];
        }
    }];
#endif
}

- (void)_takePhotoSilent
{
    if (self.isCapturingImage) {
        return;
    }
    self.isCapturingImage = YES;
    self.isTakingPhotoSilent = YES;
}

#pragma mark - Capturing Video

- (void)startRecordingVideo {
    AVCaptureConnection *videoConnection = _stillCamera.videoCaptureConnection;
    
    if ([videoConnection isVideoOrientationSupported]) {
        [videoConnection setVideoOrientation:[self _currentCaptureVideoOrientationForDevice]];
    }
    
    /*
     if ([videoConnection isVideoMirroringSupported]) {
     [videoConnection setVideoMirrored:(_cameraDevice == FastttCameraDeviceFront)];
     }
     */
    
    NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Movie.m4v"];
    unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    _movieURL = [NSURL fileURLWithPath:pathToMovie];
    
    CGFloat ratio = _previewView.bounds.size.height/_previewView.bounds.size.width;
    
    if (ratio >= 1.5) {
        _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
        [self zoomToScale:_currentZoomScale];
    }
    
    AVCaptureVideoDataOutput *output = _stillCamera.captureSession.outputs.firstObject;
    NSDictionary* outputSettings = [output videoSettings];
    
    long width  = [[outputSettings objectForKey:@"Width"]  longValue];
    long height = [[outputSettings objectForKey:@"Height"] longValue];
    
    if (UIInterfaceOrientationIsPortrait([_stillCamera outputImageOrientation])) {
        long buf = width;
        width = height;
        height = buf;
    }
    
    _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:_movieURL size:CGSizeMake(width, height)];
    _movieWriter.encodingLiveVideo = YES;
    
    [self.fastFilter.filter addTarget: _movieWriter];
    _stillCamera.audioEncodingTarget = _movieWriter;
    [_movieWriter startRecording];
    
}

- (void)stopRecordingVideo {
    [_movieWriter finishRecordingWithCompletionHandler:^{
        [self.fastFilter.filter removeTarget:_movieWriter];
        _stillCamera.audioEncodingTarget = nil;
        _movieWriter = nil;
        [self _processCameraVideo];
        
        CGFloat ratio = _previewView.bounds.size.height/_previewView.bounds.size.width;
        
        if (ratio >= 1.5) {
            _stillCamera.captureSessionPreset = AVCaptureSessionPresetPhoto;
            [self zoomToScale:_currentZoomScale];
        }
    }];
}

#pragma mark - Processing a Photo

- (void)_processCameraPhoto:(UIImage *)image needsPreviewRotation:(BOOL)needsPreviewRotation imageOrientation:(UIImageOrientation)imageOrientation previewOrientation:(UIDeviceOrientation)previewOrientation
{
    CGRect cropRect = CGRectNull;
    if (self.cropsImageToVisibleAspectRatio) {
        cropRect = [image fastttCropRectFromPreviewBounds:_previewView.frame];
    }
    
    [self _processImage:image withCropRect:cropRect maxDimension:self.maxScaledDimension fromCamera:YES needsPreviewRotation:(needsPreviewRotation || !self.interfaceRotatesWithOrientation) imageOrientation:imageOrientation previewOrientation:previewOrientation];
}

- (void)_processImage:(UIImage *)image withCropRect:(CGRect)cropRect maxDimension:(CGFloat)maxDimension fromCamera:(BOOL)fromCamera needsPreviewRotation:(BOOL)needsPreviewRotation previewOrientation:(UIDeviceOrientation)previewOrientation
{
    [self _processImage:image withCropRect:cropRect maxDimension:maxDimension fromCamera:fromCamera needsPreviewRotation:needsPreviewRotation imageOrientation:image.imageOrientation previewOrientation:previewOrientation];
}

- (void)_processImage:(UIImage *)image withCropRect:(CGRect)cropRect maxDimension:(CGFloat)maxDimension fromCamera:(BOOL)fromCamera needsPreviewRotation:(BOOL)needsPreviewRotation imageOrientation:(UIImageOrientation)imageOrientation previewOrientation:(UIDeviceOrientation)previewOrientation

{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (fromCamera && !self.isCapturingImage) {
            return;
        }
        
        UIImage *fixedOrientationImage = [image fastttRotatedImageMatchingOrientation:imageOrientation];
        
        FastttCapturedImage *capturedImage = [FastttCapturedImage fastttCapturedFullImage:fixedOrientationImage];
        
        [capturedImage cropToRect:cropRect
                   returnsPreview:(fromCamera && self.returnsRotatedPreview)
             needsPreviewRotation:needsPreviewRotation
           withPreviewOrientation:previewOrientation
                     withCallback:^(FastttCapturedImage *capturedImage){
                         if (fromCamera && !self.isCapturingImage) {
                             return;
                         }
                         capturedImage.rotatedPreviewImage = [capturedImage.rotatedPreviewImage fastttRotatedImageMatchingOrientation:UIImageOrientationUp];
                         
                         if ([self.delegate respondsToSelector:@selector(cameraController:didFinishCapturingImage:)]) {
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 [self.delegate cameraController:self didFinishCapturingImage:capturedImage];
                             });
                         }
                         
                         [self.currentMetadata setObject:[NSNumber numberWithInt:imageOrientation]
                                                  forKey:(NSString *)kCGImagePropertyOrientation];
                         NSLog(@"%@", self.currentMetadata);
                         
                         NSData *imageData = [self createImageDataFromImage:capturedImage.fullImage metaData:self.currentMetadata];
                         
                         if ([self.delegate respondsToSelector:@selector(cameraController:didFinishCapturingImageData:)]) {
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 [self.delegate cameraController:self didFinishCapturingImageData:imageData];
                             });
                         }
                     }];
        
        void (^scaleCallback)(FastttCapturedImage *capturedImage) = ^(FastttCapturedImage *capturedImage) {
            if (fromCamera && !self.isCapturingImage) {
                return;
            }
            if ([self.delegate respondsToSelector:@selector(cameraController:didFinishScalingCapturedImage:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate cameraController:self didFinishScalingCapturedImage:capturedImage];
                });
            }
        };
        
        if (fromCamera && !self.isCapturingImage) {
            return;
        }
        
        if (maxDimension > 0.f) {
            [capturedImage scaleToMaxDimension:maxDimension
                                  withCallback:scaleCallback];
        } else if (fromCamera && self.scalesImage) {
            [capturedImage scaleToSize:self.view.bounds.size
                          withCallback:scaleCallback];
        }
        
        if (fromCamera && !self.isCapturingImage) {
            return;
        }
        
        if (self.normalizesImageOrientations) {
            [capturedImage normalizeWithCallback:^(FastttCapturedImage *capturedImage){
                if (fromCamera && !self.isCapturingImage) {
                    return;
                }
                if ([self.delegate respondsToSelector:@selector(cameraController:didFinishNormalizingCapturedImage:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate cameraController:self didFinishNormalizingCapturedImage:capturedImage];
                    });
                }
            }];
        }
        
        self.isCapturingImage = NO;
    });
}

#pragma mark - Processing a Video

- (void)_processCameraVideo {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // output file
        NSString* docFolder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        NSString* outputPath = [docFolder stringByAppendingPathComponent:@"Output.mov"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath])
            [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
        
        // input file
        AVAsset* asset = [AVAsset assetWithURL:_movieURL];
        
        AVMutableComposition *composition = [AVMutableComposition composition];
        [composition  addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        // input clip
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        
        // crop clip to screen ratio
        UIInterfaceOrientation orientation = [self orientationForTrack:asset];
        BOOL isPortrait = (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) ? YES: NO;
        CGFloat complimentSize = [self getComplimentSize:videoTrack.naturalSize.width];
        CGSize videoSize;
        
        if(isPortrait) {
            videoSize = CGSizeMake(complimentSize, videoTrack.naturalSize.width);
        } else {
            videoSize = CGSizeMake(videoTrack.naturalSize.width, complimentSize);
        }
        
        AVMutableVideoComposition* videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.renderSize = videoSize;
        videoComposition.frameDuration = CMTimeMake(1, 30);
        
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        
        // rotate and position video
        AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        
        CGFloat tx = (videoTrack.naturalSize.height-complimentSize)/2;
        
        if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationLandscapeRight) {
            // invert translation
            tx *= -1;
        }
        
        CGAffineTransform t;
        
        // t1: rotate and position video since it may have been cropped to screen ratio
        CGAffineTransform t1 = CGAffineTransformTranslate(videoTrack.preferredTransform, 0, tx);
        t = t1;
        // t2/t3: mirror video horizontally
        /*    if (_cameraDevice == FastttCameraDeviceFront) {
         CGAffineTransform t2 = CGAffineTransformTranslate(t1, isPortrait?0:videoTrack.naturalSize.width, isPortrait?videoTrack.naturalSize.height:0);
         CGAffineTransform t3 = CGAffineTransformScale(t2, isPortrait?1:-1, isPortrait?-1:1);
         t = t3;
         }*/
        
        [transformer setTransform:t atTime:kCMTimeZero];
        instruction.layerInstructions = [NSArray arrayWithObject: transformer];
        videoComposition.instructions = [NSArray arrayWithObject: instruction];
        
        // export
        AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality] ;
        exporter.videoComposition = videoComposition;
        exporter.outputURL = outputURL;
        exporter.outputFileType = AVFileTypeQuickTimeMovie;
        
        [exporter exportAsynchronouslyWithCompletionHandler:^(void){
            NSLog(@"Exporting done!");
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(cameraController:didFinishRecordingVideo:)]) {
                    [self.delegate cameraController:self didFinishRecordingVideo:outputURL];
                }
            });
        }];
    });
}

- (CGFloat)getComplimentSize:(CGFloat)size {
    CGSize previewSize = _previewView.bounds.size;
    
    if (_stillCamera.outputImageOrientation == UIImageOrientationRight
        || _stillCamera.outputImageOrientation == UIImageOrientationLeft
        || _stillCamera.outputImageOrientation == UIImageOrientationRightMirrored
        || _stillCamera.outputImageOrientation == UIImageOrientationLeftMirrored) {
        
        previewSize = CGSizeMake(previewSize.height, previewSize.width);
    }
    
    CGFloat ratio = previewSize.height / previewSize.width;
    
    // we have to adjust the ratio for 16:9 screens
    if (ratio == 1.775) ratio = 1.77777777777778;
    
    return size * ratio;
}

- (UIInterfaceOrientation)orientationForTrack:(AVAsset *)asset {
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    
    if([tracks count] > 0) {
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        CGAffineTransform t = videoTrack.preferredTransform;
        
        // Portrait
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0) {
            orientation = UIInterfaceOrientationPortrait;
        }
        // PortraitUpsideDown
        if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0) {
            orientation = UIInterfaceOrientationPortraitUpsideDown;
        }
        // LandscapeRight
        if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0) {
            orientation = UIInterfaceOrientationLandscapeRight;
        }
        // LandscapeLeft
        if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0) {
            orientation = UIInterfaceOrientationLandscapeLeft;
        }
    }
    return orientation;
}

#pragma mark - AV Orientation

- (void)_setPreviewVideoOrientation
{
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    if (orientation == UIDeviceOrientationUnknown
        || orientation == UIDeviceOrientationFaceUp
        || orientation == UIDeviceOrientationFaceDown) {
        orientation = UIDeviceOrientationPortrait;
    }
    
    if (!self.interfaceRotatesWithOrientation) {
        orientation = self.fixedInterfaceOrientation;
    }
    
    _stillCamera.outputImageOrientation = (UIInterfaceOrientation)orientation;
}

- (UIDeviceOrientation)_currentPreviewDeviceOrientation
{
    if (!self.interfaceRotatesWithOrientation) {
        return self.fixedInterfaceOrientation;
    }
    
    return [[UIDevice currentDevice] orientation];
}

+ (UIImageOrientation)_imageOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait:
            return UIImageOrientationRight;
            
        case UIDeviceOrientationPortraitUpsideDown:
            return UIImageOrientationLeft;
            
        case UIDeviceOrientationLandscapeLeft:
            return UIImageOrientationUp;
            
        case UIDeviceOrientationLandscapeRight:
            return UIImageOrientationDown;
            
        default:
            break;
    }
    
    return UIImageOrientationRight;
}

- (AVCaptureVideoOrientation)_currentCaptureVideoOrientationForDevice
{
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    if (_cameraDevice == FastttCameraDeviceFront) {
        videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
    }
    
    return videoOrientation;
}

- (AVCaptureVideoOrientation)_currentPreviewVideoOrientationForDevice
{
    UIDeviceOrientation deviceOrientation = [self _currentPreviewDeviceOrientation];
    
    return [self.class _videoOrientationForDeviceOrientation:deviceOrientation];
}

+ (AVCaptureVideoOrientation)_videoOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    /*    if (_cameraDevice == FastttCameraDeviceFront) {
     videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
     }
     */
    /*
     switch (deviceOrientation) {
     case UIDeviceOrientationPortrait:
     return videoOrientation;
     
     case UIDeviceOrientationPortraitUpsideDown:
     return videoOrientation;
     
     case UIDeviceOrientationLandscapeLeft:
     return videoOrientation;
     
     case UIDeviceOrientationLandscapeRight:
     return videoOrientation;
     
     default:
     break;
     }
     */
    
    return videoOrientation;
}

- (UIImageOrientation)_outputImageOrientation
{
    if (![self.deviceOrientation deviceOrientationMatchesInterfaceOrientation]
        || !self.interfaceRotatesWithOrientation) {
        
        if (self.deviceOrientation.orientation == UIDeviceOrientationLandscapeLeft) {
            return UIImageOrientationLeft;
        } else if (self.deviceOrientation.orientation == UIDeviceOrientationLandscapeRight) {
            return UIImageOrientationRight;
        }
    }
    
    return UIImageOrientationUp;
}

#pragma mark - Camera Permissions

- (void)_checkDeviceAuthorizationWithCompletion:(void (^)(BOOL isAuthorized))completion
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        if (completion) {
            completion(granted);
        }
    }];
}

#pragma mark - FastttCameraDevice

- (AVCaptureDevice *)_currentCameraDevice
{
    return _stillCamera.inputCamera;
}

- (CGPoint)_focusPointOfInterestForTouchPoint:(CGPoint)touchPoint
{
    CGPoint pointOfInterest = CGPointMake(0.5f, 0.5f);
    CGSize frameSize = [_previewView frame].size;
    
    for (AVCaptureInputPort *port in [[[_stillCamera.captureSession inputs] lastObject] ports]) {
        if ([port mediaType] == AVMediaTypeVideo) {
            
            CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture([port formatDescription], NO);
            CGSize apertureSize = cleanAperture.size;
            CGPoint point = touchPoint;
            
            CGFloat apertureRatio = apertureSize.height / apertureSize.width;
            CGFloat viewRatio = frameSize.width / frameSize.height;
            CGFloat xc = .5f;
            CGFloat yc = .5f;
            
            if (viewRatio > apertureRatio) {
                CGFloat y2 = apertureSize.width * (frameSize.width / apertureSize.height);
                xc = (point.y + ((y2 - frameSize.height) / 2.f)) / y2;
                yc = (frameSize.width - point.x) / frameSize.width;
            } else {
                CGFloat x2 = apertureSize.height * (frameSize.height / apertureSize.width);
                yc = 1.f - ((point.x + ((x2 - frameSize.width) / 2)) / x2);
                xc = point.y / frameSize.height;
            }
            pointOfInterest = CGPointMake(xc, yc);
        }
    }
    
    return pointOfInterest;
}

- (BOOL)_focusAtPointOfInterest:(CGPoint)pointOfInterest
{
    return [[self _currentCameraDevice] focusAtPointOfInterest:pointOfInterest];
}

- (void)_resetZoom
{
    [self.fastZoom resetZoom];
    
    self.fastZoom.maxScale = [[self _currentCameraDevice] videoMaxZoomFactor];
    
    self.maxZoomFactor = self.fastZoom.maxScale;
}

#pragma mark - FastttFocusDelegate

- (BOOL)handleTapFocusAtPoint:(CGPoint)touchPoint
{
    if ([AVCaptureDevice isPointFocusAvailableForCameraDevice:self.cameraDevice]) {
        
        CGPoint pointOfInterest = [self _focusPointOfInterestForTouchPoint:touchPoint];
        
        return ([self _focusAtPointOfInterest:pointOfInterest] && self.showsFocusView);
    }
    
    return NO;
}

#pragma mark - FastttZoomDelegate

- (BOOL)handlePinchZoomWithScale:(CGFloat)zoomScale
{
    return ([self zoomToScale:zoomScale] && self.showsZoomView);
}

#pragma mark - GPUImageVideoCameraDelegate

- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    
    if (!self.isTakingPhotoSilent) {
        return;
    }
    
    self.isTakingPhotoSilent = NO;
    
    BOOL needsPreviewRotation = ![self.deviceOrientation deviceOrientationMatchesInterfaceOrientation];
#if TARGET_IPHONE_SIMULATOR
    UIImage *fakeImage = [UIImage fastttFakeTestImage];
    [self _processCameraPhoto:fakeImage needsPreviewRotation:needsPreviewRotation imageOrientation:UIImageOrientationUp previewOrientation:UIDeviceOrientationPortrait];
#else
    UIDeviceOrientation previewOrientation = [self _currentPreviewDeviceOrientation];
    
    UIImageOrientation outputImageOrientation = [self _outputImageOrientation];
    
    if (!sampleBuffer) {
        return;
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    CMAttachmentMode attachmentMode;
    
    // Exif
    CFDictionaryRef exifAttachments = CMGetAttachment(sampleBuffer, kCGImagePropertyExifDictionary, &attachmentMode);
    if(exifAttachments){
        [metadata setObject:(__bridge id _Nonnull)(exifAttachments) forKey:(NSString *)kCGImagePropertyExifDictionary];
    }
    // TIFF
    CFDictionaryRef tiffAttachments = CMGetAttachment(sampleBuffer, kCGImagePropertyTIFFDictionary, &attachmentMode);
    if(tiffAttachments){
        [metadata setObject:(__bridge id _Nonnull)(tiffAttachments) forKey:(NSString *)kCGImagePropertyTIFFDictionary];
    }
    
    self.currentMetadata = metadata;
    
    [self.fastFilter.filter useNextFrameForImageCapture];
    [_stillCamera processVideoSampleBuffer: sampleBuffer];
    UIImage *currentFilteredImage = [self.fastFilter.filter imageFromCurrentFramebuffer];
    
    if (self.isCapturingImage) {
        [self _processCameraPhoto:currentFilteredImage needsPreviewRotation:needsPreviewRotation imageOrientation:outputImageOrientation previewOrientation:previewOrientation];
    }
#endif
    sleep(1);
}

- (NSData *)createImageDataFromImage:(UIImage *)image metaData:(NSDictionary *)metadata
{
    // メタデータ付きの静止画データの格納先を用意する
    NSMutableData *imageData = [NSMutableData new];
    // imageDataにjpegで１枚画像を書き込む設定のCGImageDestinationRefを作成する
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, kUTTypeJPEG, 1, NULL);
    // 作成したCGImageDestinationRefに静止画データとメタデータを追加する
    CGImageDestinationAddImage(dest, image.CGImage, (__bridge CFDictionaryRef)metadata);
    // メタデータ付きの静止画データの作成を実行する
    CGImageDestinationFinalize(dest);
    // CGImageDestinationRefを解放する
    CFRelease(dest);
    
    return imageData;
}

@end
