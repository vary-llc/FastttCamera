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
#import "UIImage+FastttCamera.h"
#import "AVCaptureDevice+FastttCamera.h"
#import "FastttFocus.h"
#import "FastttFilter.h"
#import "FastttCapturedImage+Process.h"

@interface FastttFilterCamera () <FastttFocusDelegate, FastttZoomDelegate, GPUImageVideoCameraDelegate>
{
    NSURL *movieURL;
    NSMutableArray *trackingImages;
    GPUImageUIElement *uiElementInput;
    GPUImageTransformFilter *transformFilter;
    BOOL isFaceDetecting;
    CIDetector *faceDetector;
}
@property (nonatomic, strong) FastttFocus *fastFocus;
@property (nonatomic, strong) GPUImageStillCamera *stillCamera;
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
@property (nonatomic, strong) FastttFilter *fastFilter;
@property (nonatomic, strong) GPUImageView *previewView;
@property (nonatomic, assign) BOOL deviceAuthorized;
@property (nonatomic, assign) BOOL isCapturingImage;
@property (nonatomic, assign) BOOL isTakingPhotoSilent;
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
cameraTorchMode = _cameraTorchMode;

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
        _scalesImage = YES;
        _maxScaledDimension = 0.f;
        _normalizesImageOrientations = YES;
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
    if ([[self _currentCameraDevice] zoomToScale:scale]){
        [self.fastZoom showZoomViewWithScale:scale];
        return YES;
    }
    
    return NO;
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
    
    _stillCamera.captureSessionPreset = AVCaptureSessionPresetInputPriority;

    if (_cameraDevice != cameraDevice) {
        _cameraDevice = cameraDevice;
    }

    if (_stillCamera.cameraPosition != [AVCaptureDevice positionForCameraDevice:cameraDevice]) {
        [_stillCamera rotateCamera];
    }
    
    if (cameraDevice == FastttCameraDeviceFront) {
        _previewView.transform = CGAffineTransformMakeScale(-1, 1);
    }else{
        _previewView.transform = CGAffineTransformIdentity;
    }
    
    [self setCameraFlashMode:_cameraFlashMode];
    
    [self _resetZoom];
    
    [self setupCaptureSessionPreset];

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

- (GPUImageFilterGroup *)createFilterGroup:(NSArray *)filters{
    GPUImageFilterGroup *filterGroup = [[GPUImageFilterGroup alloc] init];
    GPUImageFilter *beforeFilter = nil;
    for (GPUImageFilter *filter in filters) {
        [filterGroup addTarget:filter];
        if (!beforeFilter){
            beforeFilter = filter;
            continue;
        }
        [beforeFilter addTarget:filter];
        beforeFilter = filter;
    }
    GPUImageFilter *firstFilter = [filters objectAtIndex:0];
    [filterGroup setInitialFilters:@[firstFilter]];
    GPUImageFilter *endFilter = [filters lastObject];
    [filterGroup setTerminalFilter:endFilter];
    return filterGroup;
}

#pragma mark - Capture Session Management

- (void)startRunning
{
    [_stillCamera startCameraCapture];
}

- (void)stopRunning
{
    [_stillCamera stopCameraCapture];
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

    NSMutableArray *filters = [NSMutableArray array];
    [filters addObject:[GPUImageFilter new]];
    if (self.isBeautify) {
        GPUImageBilateralFilter *bilateralFilter = [[GPUImageBilateralFilter alloc] init];
        bilateralFilter.distanceNormalizationFactor = 5.0;
        [filters addObject:bilateralFilter];
        
        GPUImageBrightnessFilter *brightnessFilter = [[GPUImageBrightnessFilter alloc]init];
        brightnessFilter.brightness = 0.03;
        [filters addObject:brightnessFilter];
    }

    if (_previewView.bounds.size.width == _previewView.bounds.size.height){
        GPUImageCropFilter *cropFilter = [[GPUImageCropFilter alloc]initWithCropRegion:CGRectMake(0, 0.125f, 1.0f, 0.75f)];
        [filters addObject:cropFilter];
    }
        
    /*
    AVCaptureVideoDataOutput *output = _stillCamera.captureSession.outputs.firstObject;
    if (output) {
        NSDictionary* outputSettings = [output videoSettings];
        
        long width  = [[outputSettings objectForKey:@"Width"]  longValue];
        long height = [[outputSettings objectForKey:@"Height"] longValue];
        
        CGFloat previewWidth = _previewView.bounds.size.width;
        CGFloat previewHeight = _previewView.bounds.size.height;
        CGFloat captureWidth = height;
        CGFloat captureHeight = width;
        CGFloat cropHeight = (captureWidth / previewWidth * previewHeight) / captureHeight;
        if (cropHeight > 1) {
            cropHeight = 1;
        }
        CGFloat cropY = (1 - cropHeight) / 2;
        
        GPUImageCropFilter *cropFilter = [[GPUImageCropFilter alloc]initWithCropRegion:CGRectMake(0, cropY, 1.0f, cropHeight)];
        [_stillCamera addTarget:cropFilter];
        [cropFilter addTarget:self.fastFilter.filter];
    }else{
        [_stillCamera addTarget:self.fastFilter.filter];
    }
    */
    
    GPUImageFilterGroup *groupFilter = [self createFilterGroup: filters];
    [_stillCamera addTarget:groupFilter];
    
    if (self.watermarkView) {
        self.watermarkView.frame = _previewView.bounds;
        GPUImageAlphaBlendFilter *blendFilter = [[GPUImageAlphaBlendFilter alloc] init];
        blendFilter.mix = 0.75;
        uiElementInput = [[GPUImageUIElement alloc] initWithView:self.watermarkView];
        transformFilter = [[GPUImageTransformFilter alloc]init];
        [groupFilter addTarget:blendFilter];
        [uiElementInput addTarget:transformFilter];
        [transformFilter addTarget:blendFilter];
        [blendFilter addTarget:self.fastFilter.filter];
        [self.fastFilter.filter addTarget:_previewView];

        __unsafe_unretained GPUImageUIElement *weakUIElementInput = uiElementInput;
        __unsafe_unretained GPUImageTransformFilter *weakTransformFilter = transformFilter;
        __unsafe_unretained FastttCameraDevice *weakCameraDevice = _cameraDevice;
        __weak typeof(self) weakSelf = self;
        
        [groupFilter setFrameProcessingCompletionBlock:^(GPUImageOutput * filter, CMTime frameTime){
            @autoreleasepool {
                CGAffineTransform transform = CGAffineTransformIdentity;
                
                switch ([weakSelf _outputImageOrientation]) {
                    case UIImageOrientationUp:
                    case UIImageOrientationUpMirrored:
                        transform = CGAffineTransformIdentity;
                        break;
                    case UIImageOrientationDown:
                    case UIImageOrientationDownMirrored:
                        transform = CGAffineTransformMakeRotation((180.0 * M_PI) / 180.0);
                        break;
                    case UIImageOrientationLeft:
                    case UIImageOrientationRightMirrored:
                        transform = CGAffineTransformMakeRotation((90.0 * M_PI) / 180.0);
                        break;
                    case UIImageOrientationRight:
                    case UIImageOrientationLeftMirrored:
                        transform = CGAffineTransformMakeRotation((270.0 * M_PI) / 180.0);
                        break;
                    default:
                        transform = CGAffineTransformIdentity;
                        break;
                }
                
                [weakTransformFilter setAffineTransform:transform];
                [weakUIElementInput update];
            }

        }];
    }else{
        [groupFilter addTarget:self.fastFilter.filter];
        [self.fastFilter.filter addTarget:_previewView];
    }
}

- (void)_removePreviewLayer
{
    [_stillCamera removeAllTargets];
    [self.fastFilter.filter removeAllTargets];
    
    [_previewView removeFromSuperview];
    _previewView = nil;
}

- (void)setupCaptureSessionPreset
{
    if (self.isVideoCamera) {
        if ([_stillCamera.captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160] && self.cameraDevice == FastttCameraDeviceRear){
            _stillCamera.captureSessionPreset = AVCaptureSessionPreset3840x2160;
        }else{
            _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
        }
        //[self _setupCaptureDeviceFormatWithHighestFps];
    }else{
        //_stillCamera.captureSessionPreset = AVCaptureSessionPresetPhoto;
        [self _setupCaptureDeviceFormatWithLargestHeight];
    }
    
    //isFaceDetecting = YES;
}

- (void)_setupCaptureDeviceFormatWithHighestFps
{
    _stillCamera.captureSessionPreset = AVCaptureSessionPresetInputPriority;
    
    if (!_stillCamera.inputCamera) return;
    
    NSArray *formats = _stillCamera.inputCamera.formats;
    
    Float64 maxFrameRate = .0f;
    int32_t maxWidth = 0;
    AVCaptureDeviceFormat *targetFormat = nil;
    for (AVCaptureDeviceFormat *format in formats) {
        AVFrameRateRange *frameRateRange = format.videoSupportedFrameRateRanges[0];
        Float64 frameRate = frameRateRange.maxFrameRate;
        
        CMFormatDescriptionRef desc = format.formatDescription;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
        int32_t width = dimensions.width;
        
        if (frameRate >= maxFrameRate && width >= maxWidth) {
            targetFormat = format;
            
            maxFrameRate = frameRate;
            maxWidth = width;
        }
    }
    
    if (!targetFormat) return;
    
    if([_stillCamera.inputCamera lockForConfiguration: nil]){
        _stillCamera.inputCamera.activeFormat = targetFormat;
        [_stillCamera setFrameRate: maxFrameRate];
        [_stillCamera.inputCamera unlockForConfiguration];
    }
}

- (void)_setupCaptureDeviceFormatWithLargestHeight
{
    _stillCamera.captureSessionPreset = AVCaptureSessionPresetInputPriority;
    
    if (!_stillCamera.inputCamera) return;
    
    NSArray *formats = _stillCamera.inputCamera.formats;
    
    int32_t maxHeight = 0;
    AVCaptureDeviceFormat *targetFormat = nil;
    for (AVCaptureDeviceFormat *format in formats) {        
        CMFormatDescriptionRef desc = format.formatDescription;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
        int32_t height = dimensions.height;
        if ( height >= maxHeight) {
            targetFormat = format;
            maxHeight = height;
        }
    }
    
    if (!targetFormat) return;

    if([_stillCamera.inputCamera lockForConfiguration: nil]){
        _stillCamera.inputCamera.activeFormat = targetFormat;
        [_stillCamera.inputCamera unlockForConfiguration];
    }
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
                    //device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                    NSArray *deviceTypes = @[AVCaptureDeviceTypeBuiltInDuoCamera, AVCaptureDeviceTypeBuiltInWideAngleCamera];
                    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
                    NSArray *devices = [discoverySession devices];
                    device = devices.lastObject;
                }
                
                AVCaptureDevicePosition position = [device position];
                
                _stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetInputPriority cameraPosition:position];
                _stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
                //_stillCamera.horizontallyMirrorFrontFacingCamera = YES;
                _stillCamera.delegate = self;
                
                if (_stillCamera.videoCaptureConnection.supportsVideoStabilization){
                    _stillCamera.videoCaptureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
                }
                
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
                    [self setupCaptureSessionPreset];
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
    
    [_stillCamera capturePhotoAsJPEGProcessedUpToFilter:self.fastFilter.filter withOrientation:outputImageOrientation withCompletionHandler:^(NSData *processedJPEG, NSError *error){
        
        if (self.isCapturingImage) {
            if ([self.delegate respondsToSelector:@selector(cameraController:didFinishCapturingImageData:)]) {
                [self.delegate cameraController:self didFinishCapturingImageData:processedJPEG];
                self.isCapturingImage = NO;
            }else{
                UIImage *processedImage = [UIImage imageWithData:processedJPEG];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self _processCameraPhoto:processedImage needsPreviewRotation:needsPreviewRotation imageOrientation:outputImageOrientation previewOrientation:previewOrientation];
                });
            }

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

- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }
    
    if (isFaceDetecting) {
        
        if (!faceDetector) {
            NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
            faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
        }
        
        // got an image
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
        CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
        if (attachments)
            CFRelease(attachments);
        
        NSDictionary *imageOptions = nil;
        int exifOrientation;
        
        enum {
            PHOTOS_EXIF_0ROW_TOP_0COL_LEFT                  = 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
            PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT                 = 2, //   2  =  0th row is at the top, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
            PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
            PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
        };
        exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
        
        imageOptions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:exifOrientation] , CIDetectorImageOrientation,[NSNumber numberWithBool:YES],CIDetectorEyeBlink,nil];
        NSArray *features = [faceDetector featuresInImage:ciImage options:imageOptions];
        
        // get the clean aperture
        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
        // that represents image data valid for display.
        //CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        //CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, originIsTopLeft == false);
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            for(CIFaceFeature* face in features){
                // 座標変換
                CGRect faceRect = face.bounds;
                CGFloat widthPer = (self.view.bounds.size.width/ciImage.extent.size.width);
                CGFloat heightPer = (self.view.bounds.size.height/ciImage.extent.size.height);
                
                // UIKitは左上に原点があるが、CoreImageは左下に原点があるので揃える
                faceRect.origin.y = ciImage.extent.size.height - faceRect.origin.y - faceRect.size.height;
                
                //倍率変換
                faceRect.origin.x = faceRect.origin.x * widthPer;
                faceRect.origin.y = faceRect.origin.y * heightPer;
                faceRect.size.width = faceRect.size.width * widthPer;
                faceRect.size.height = faceRect.size.height * heightPer;
                
                CGPoint facePoint = CGPointMake(CGRectGetMidX(faceRect), CGRectGetMidY(faceRect));
                [self _focusAtPointOfInterest:facePoint];
                [self.fastFocus showFocusViewAtPoint:facePoint];
                isFaceDetecting = NO;
                
            }
        });
    }
    
    if (self.isTracking) {
        if (!trackingImages) {
            trackingImages = [NSMutableArray new];
            CGFloat width  = 507;
            if (_previewView.bounds.size.width == _previewView.bounds.size.height) {
                width  = width * 1.1547;
                [self.fastFilter.filter forceProcessingAtSize:CGSizeMake(width, width)];
            }else{
                [self.fastFilter.filter forceProcessingAtSize:CGSizeMake(width, width/3*4)];
            }
        }else{
            [self.fastFilter.filter useNextFrameForImageCapture];
            [_stillCamera processVideoSampleBuffer: sampleBuffer];
            UIImageOrientation outputImageOrientation = [self _outputImageOrientation];
            UIImage *processedImage = [self.fastFilter.filter imageFromCurrentFramebufferWithOrientation:outputImageOrientation];
            CFDictionaryRef metadataRef = CMCopyDictionaryOfAttachments(NULL, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
            NSDictionary *metadata = ((__bridge_transfer NSDictionary *)metadataRef);
            NSData *processedJPEG = [self createImageDataFromImage:processedImage metaData: metadata];
            [trackingImages addObject:processedJPEG];
        }
    }else if (trackingImages) {
        AVFrameRateRange *frameRateRange = _stillCamera.inputCamera.activeFormat.videoSupportedFrameRateRanges[0];
        Float64 frameRate = frameRateRange.maxFrameRate;
        [self.delegate cameraController:self didFinishCapturedImages:trackingImages.copy frameRate:frameRate];
        trackingImages = nil;
        [self.fastFilter.filter forceProcessingAtSize:CGSizeZero];
    }

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
    
    [self.fastFilter.filter useNextFrameForImageCapture];
    [_stillCamera processVideoSampleBuffer: sampleBuffer];
    UIImage *processedImage = [self.fastFilter.filter imageFromCurrentFramebufferWithOrientation:outputImageOrientation];
    CFDictionaryRef metadataRef = CMCopyDictionaryOfAttachments(NULL, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    NSDictionary *metadata = ((__bridge_transfer NSDictionary *)metadataRef);
    NSData *processedJPEG = [self createImageDataFromImage:processedImage metaData: metadata];
    
    if (self.isCapturingImage) {
        if ([self.delegate respondsToSelector:@selector(cameraController:didFinishCapturingImageData:)]) {
            [self.delegate cameraController:self didFinishCapturingImageData:processedJPEG];
            self.isCapturingImage = NO;
        }else{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self _processCameraPhoto:processedImage needsPreviewRotation:needsPreviewRotation imageOrientation:outputImageOrientation previewOrientation:previewOrientation];
            });
        }
    }
#endif
}

- (NSData *)createImageDataFromImage:(UIImage *)image metaData:(NSDictionary *)metadata
{
    NSMutableDictionary *fixedMetadata = metadata.mutableCopy;
    NSMutableDictionary *tiff = [[metadata objectForKey:(NSString *)kCGImagePropertyTIFFDictionary] mutableCopy];
    [fixedMetadata setObject:[self _exifOrientation] forKey:(NSString *)kCGImagePropertyOrientation];
    [tiff setObject:[self _exifOrientation] forKey:(NSString *)kCGImagePropertyTIFFOrientation];
    [fixedMetadata setObject:tiff.copy forKey:(NSString *)kCGImagePropertyTIFFDictionary];
    
    NSMutableData *imageData = [NSMutableData new];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, kUTTypeJPEG, 1, NULL);
    CGImageDestinationAddImage(dest, image.CGImage, (__bridge CFDictionaryRef)fixedMetadata.copy);
    CGImageDestinationFinalize(dest);
    CFRelease(dest);
    
    return imageData;
}

#pragma mark - Recording a Video

- (void)startRecordingVideo
{
    if (!_deviceAuthorized) {
        return;
    }
    
    if (!_movieWriter) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *path = [NSString stringWithFormat:@"Documents/%@.M4V", [formatter stringFromDate:[NSDate date]]];
        NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:path];
        unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
        movieURL = [NSURL fileURLWithPath:pathToMovie];
        
        AVCaptureVideoDataOutput *output = _stillCamera.captureSession.outputs.firstObject;
        NSDictionary* outputSettings = [output videoSettings];
        
        long width  = [[outputSettings objectForKey:@"Width"]  longValue];
        long height = [[outputSettings objectForKey:@"Height"] longValue];
        long maxWidth = 1920;
        if (width > maxWidth) {
            double ratio = (double)height / (double)width;
            width = maxWidth;
            height = width * ratio;
        }
        
        switch ([self _outputImageOrientation]) {
            case UIImageOrientationUp:
            case UIImageOrientationDown:
            case UIImageOrientationUpMirrored:
            case UIImageOrientationDownMirrored:
            {
                long buf = width;
                width = height;
                height = buf;
            }
                break;
            default:
                break;
        }
        
        _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:movieURL size:CGSizeMake(width, height)];
        _movieWriter.encodingLiveVideo = YES;
        [_movieWriter setInputRotation:[self _rotationMode] atIndex:0];
    }
    [self.fastFilter.filter addTarget:_movieWriter];
    
    _stillCamera.audioEncodingTarget = _movieWriter;
    
    double delayToStartRecording = 0.5;
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, delayToStartRecording * NSEC_PER_SEC);
    dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
        [_movieWriter startRecording];
    });
    [self setCameraTorchMode:_cameraTorchMode];
}

- (void)stopRecordingVideo
{
    
    if (!_movieWriter) {
        return;
    }
    
    [_movieWriter finishRecordingWithCompletionHandler:^{
        _stillCamera.audioEncodingTarget = nil;
        
        if ([self.delegate respondsToSelector:@selector(cameraController:didFinishRecordingVideo:)]) {
            [self.delegate cameraController:self didFinishRecordingVideo: movieURL];
        }
        [self setCameraTorchMode:_cameraTorchMode];
    }];
    
    _movieWriter = nil;
    
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

- (UIImageOrientation)_outputImageOrientation
{
    if (![self.deviceOrientation deviceOrientationMatchesInterfaceOrientation]
        || !self.interfaceRotatesWithOrientation) {
        
        if (self.deviceOrientation.orientation == UIDeviceOrientationLandscapeLeft) {
            if (self.cameraDevice == FastttCameraDeviceRear) {
                return UIImageOrientationLeft;
            }else{
                return UIImageOrientationLeftMirrored;
            }
        } else if (self.deviceOrientation.orientation == UIDeviceOrientationLandscapeRight) {
            if (self.cameraDevice == FastttCameraDeviceRear) {
                return UIImageOrientationRight;
            }else{
                return UIImageOrientationRightMirrored;
            }
        }
    }
    
    if (self.deviceOrientation.orientation == UIDeviceOrientationPortrait) {
        if (self.cameraDevice == FastttCameraDeviceRear) {
            return UIImageOrientationUp;
        }else{
            return UIImageOrientationUpMirrored;
        }
    } else if (self.deviceOrientation.orientation == UIDeviceOrientationPortraitUpsideDown) {
        if (self.cameraDevice == FastttCameraDeviceRear) {
            return UIImageOrientationDown;
        }else{
            return UIImageOrientationDownMirrored;
        }
    }
}

- (NSNumber *)_exifOrientation
{
    switch ([self _outputImageOrientation]) {
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            return [NSNumber numberWithInt:1];
            break;
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            return [NSNumber numberWithInt:3];
            break;
        case UIImageOrientationLeft:
        case UIImageOrientationRightMirrored:
            return [NSNumber numberWithInt:8];
            break;
        case UIImageOrientationRight:
        case UIImageOrientationLeftMirrored:
            return [NSNumber numberWithInt:6];
            break;
        default:
            return [NSNumber numberWithInt:1];
            break;
    }
    
    return [NSNumber numberWithInt:1];
}

/*- (NSNumber *)_exifOrientation
 {
 switch (self.deviceOrientation.orientation) {
 case UIDeviceOrientationPortrait:
 return [NSNumber numberWithInt:1];
 break;
 case UIDeviceOrientationPortraitUpsideDown:
 return [NSNumber numberWithInt:3];
 break;
 case UIDeviceOrientationLandscapeLeft:
 return [NSNumber numberWithInt:8];
 break;
 case UIDeviceOrientationLandscapeRight:
 return [NSNumber numberWithInt:6];
 break;
 default:
 return [NSNumber numberWithInt:1];
 break;
 }
 
 return [NSNumber numberWithInt:1];
 }
 */
- (GPUImageRotationMode)_rotationMode
{
        switch ([self _outputImageOrientation]) {
            case UIImageOrientationUp:
            case UIImageOrientationUpMirrored:
                return kGPUImageNoRotation;
                break;
            case UIImageOrientationDown:
            case UIImageOrientationDownMirrored:
                return kGPUImageRotate180;
                break;
            case UIImageOrientationLeft:
            case UIImageOrientationRightMirrored:
                return kGPUImageRotateLeft;
                break;           
            case UIImageOrientationRight:
            case UIImageOrientationLeftMirrored:
                return kGPUImageRotateRight;
                break;
            default:
                return kGPUImageNoRotation;
                break;
        }
    
    return kGPUImageNoRotation;
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
        isFaceDetecting = NO;
        
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

@end
