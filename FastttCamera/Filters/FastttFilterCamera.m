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
@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
@property (nonatomic, strong) FastttFilter *fastFilter;
@property (nonatomic, strong) GPUImageView *previewView;
@property (nonatomic, assign) BOOL deviceAuthorized;
@property (nonatomic, assign) BOOL isCapturingImage;
@property (nonatomic, assign) BOOL isTakingPhotoSilent;
@property (nonatomic, strong) NSURL *movieURL;
@property (nonatomic, strong) NSURL *audioURL;
@property (nonatomic, assign) CGFloat currentZoomScale;
@property (nonatomic, strong) NSMutableDictionary *currentMetadata;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;

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
    
    [self stopRecordingVideo];
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
                _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPresetLow cameraPosition:position];
                _stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:position];
                _stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
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

#pragma mark - Recording Video

- (void)startRecordingVideo {
    CGFloat ratio = _previewView.bounds.size.height/_previewView.bounds.size.width;
    if (ratio >= 1.5) {
        _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
        [self zoomToScale:_currentZoomScale];
    }
    else{
        [self startRecordAudio];
    }
    
    AVCaptureConnection *videoConnection = _stillCamera.videoCaptureConnection;
    
    if ([videoConnection isVideoOrientationSupported]) {
        [videoConnection setVideoOrientation:[self _currentCaptureVideoOrientationForDevice]];
    }
    /*
    AVCaptureSession *captureSession = _stillCamera.captureSession;
    AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];
    if (audioInput) {
        [captureSession addInput:audioInput];
    }
    else {
        // Handle the failure.
    }
    */
    
    NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Movie.m4v"];
    unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    _movieURL = [NSURL fileURLWithPath:pathToMovie];
    
    /*
     CGFloat ratio = _previewView.bounds.size.height/_previewView.bounds.size.width;
     
     if (ratio >= 1.5) {
     _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
     }else{
     _stillCamera.captureSessionPreset = AVCaptureSessionPresetInputPriority;
     
     // カメラのフォーマット一覧を取得
     NSArray *formats = _stillCamera.inputCamera.formats;
     
     // カメラのフォーマット一覧から、最高fpsかつ最大サイズのフォーマットを検索
     // （420f,420vにはこだわらない）
     Float64 maxFrameRate = .0f;
     int32_t maxWidth = 0;
     AVCaptureDeviceFormat *targetFormat = nil;
     for (AVCaptureDeviceFormat *format in formats) {
     NSLog(@"%@", format);
     // フォーマットのFPSを取得
     AVFrameRateRange *frameRateRange = format.videoSupportedFrameRateRanges[0];
     Float64 frameRate = frameRateRange.maxFrameRate; // フレームレート
     
     // フォーマットのフレームサイズ（幅）を取得
     CMFormatDescriptionRef desc = format.formatDescription;
     CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
     int32_t width = dimensions.width;                // フレームサイズ（幅）
     
     // フレームレートとサイズの両方が大きい場合はフォーマットを保持
     if (frameRate >= maxFrameRate && width >= maxWidth) {
     targetFormat = format;
     
     // 条件の更新
     maxFrameRate = frameRate;
     maxWidth = width;
     }
     }
     
     // 検索したフォーマットをデバイスに設定し、fpsを上限値で指定
     if ([_stillCamera.inputCamera lockForConfiguration:nil]) {
     _stillCamera.inputCamera.activeFormat = targetFormat;
     _stillCamera.inputCamera.activeVideoMaxFrameDuration = CMTimeMake(1, maxFrameRate);
     _stillCamera.inputCamera.activeVideoMinFrameDuration = CMTimeMake(1, maxFrameRate);
     [_stillCamera.inputCamera unlockForConfiguration];
     }
     }
     */

    AVCaptureVideoDataOutput *output = _stillCamera.captureSession.outputs.firstObject;
    NSDictionary* outputSettings = [output videoSettings];
    
    long width  = [[outputSettings objectForKey:@"Width"]  longValue];
    long height = [[outputSettings objectForKey:@"Height"] longValue];
    
    if (UIInterfaceOrientationIsPortrait([_stillCamera outputImageOrientation])) {
        long buf = width;
        width = height;
        height = buf;
    }
    
    // crop clip to screen ratio
    CGFloat complimentHeight = [self getComplimentSize:width];
    CGFloat ty = (height-complimentHeight)/2;
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformTranslate(transform, 0, -ty);
    
    _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:_movieURL size:CGSizeMake(width, complimentHeight)];
    _movieWriter.encodingLiveVideo = YES;
    //_movieWriter.shouldPassthroughAudio = YES;
    _movieWriter.transform = transform;

    //GPUImageTransformFilter *transformFilter = [[GPUImageTransformFilter alloc]init];
    //[transformFilter setAffineTransform:transform];
    
    [self.fastFilter.filter addTarget: _movieWriter];
    //[transformFilter addTarget:_movieWriter];
    
    _stillCamera.audioEncodingTarget = _movieWriter;
    [_movieWriter startRecording];
    
    [self setCameraTorchMode:_cameraTorchMode];
}

- (void)stopRecordingVideo {
    if (!_movieWriter) {
        return;
    }
    
    CGFloat ratio = _previewView.bounds.size.height/_previewView.bounds.size.width;
    if (ratio < 1.5) {
        [self stopRecordAudio];
    }
    
    [_movieWriter finishRecordingWithCompletionHandler:^{
        [self.fastFilter.filter removeTarget:_movieWriter];
        _stillCamera.audioEncodingTarget = nil;
        //[self _processCameraVideo];
        [self.delegate cameraController:self didFinishRecordingVideo: _movieURL];
        
        if (ratio >= 1.5) {
            _stillCamera.captureSessionPreset = AVCaptureSessionPresetPhoto;
            [self zoomToScale:_currentZoomScale];
        }
        
        [self setCameraTorchMode:_cameraTorchMode];
    }];
    
    _movieWriter = nil;
}

#pragma mark - Recording Audio

-(NSMutableDictionary *)setAudioRecorder
{
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
    [settings setValue:[NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
    [settings setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [settings setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
    [settings setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
    
    return settings;
}

-(void)startRecordAudio
{
    // Prepare recording(Audio session)
    NSError *error = nil;
    
    if ( [AVAudioSession sharedInstance].inputAvailable )   // for iOS6 [session inputIsAvailable]  iOS5
    {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:&error];
    }
    
    if ( error != nil )
    {
        NSLog(@"Error when preparing audio session :%@", [error localizedDescription]);
        return;
    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if ( error != nil )
    {
        NSLog(@"Error when enabling audio session :%@", [error localizedDescription]);
        return;
    }
    
    // File Path
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *filePath = [dir stringByAppendingPathComponent:@"Audio.caf"];
    _audioURL = [NSURL fileURLWithPath:filePath];
    
    _audioRecorder = [[AVAudioRecorder alloc] initWithURL:_audioURL settings:[self setAudioRecorder] error:&error];
    [_audioRecorder prepareToRecord];
    _audioRecorder.meteringEnabled = YES;
    if ( error != nil )
    {
        NSLog(@"Error when preparing audio recorder :%@", [error localizedDescription]);
        return;
    }
    [_audioRecorder record];
}

-(void)stopRecordAudio
{
    if ( _audioRecorder != nil && _audioRecorder.isRecording )
    {
        [_audioRecorder stop];
        _audioRecorder = nil;
    }
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
                         
                         NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                         [outputFormatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
                         NSString *date = [outputFormatter stringFromDate:[NSDate date]];
                         [self.currentMetadata setObject:date forKey:(NSString*)kCGImagePropertyExifDateTimeOriginal];
                         [self.currentMetadata setObject:date forKey:(NSString*)kCGImagePropertyExifDateTimeDigitized];
                         [self.currentMetadata setObject:[NSNumber numberWithInt:imageOrientation] forKey:(NSString *)kCGImagePropertyOrientation];
                         [self.currentMetadata setObject:[NSNumber numberWithInt:(int)capturedImage.fullImage.size.height] forKey:(NSString *)kCGImagePropertyPixelHeight];
                         [self.currentMetadata setObject:[NSNumber numberWithInt:(int)capturedImage.fullImage.size.width] forKey:(NSString *)kCGImagePropertyPixelWidth];
                         
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
        
        AVMutableComposition *composition = [AVMutableComposition composition];
        
        AVURLAsset* videoAsset = [AVURLAsset URLAssetWithURL:_movieURL options:nil];
        AVAssetTrack *videoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        CMTimeRange timeRange = CMTimeRangeMake(videoTrack.timeRange.start, videoTrack.timeRange.duration);

        AVMutableCompositionTrack *compositionVideoTrack = [composition  addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        [compositionVideoTrack insertTimeRange:timeRange
                                       ofTrack:videoTrack
                                        atTime:kCMTimeZero
                                         error:nil];
        
        // crop clip to screen ratio
        UIInterfaceOrientation orientation = [self orientationForTrack:videoAsset];
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
        instruction.timeRange = timeRange;

        // rotate and position video
        AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        
        CGFloat tx = (videoTrack.naturalSize.height-complimentSize)/2;
        
        if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationLandscapeRight) {
            // invert translation
            tx *= -1;
        }
        
        // t: rotate and position video since it may have been cropped to screen ratio
        CGAffineTransform t = CGAffineTransformTranslate(videoTrack.preferredTransform, 0, tx);
        [transformer setTransform:t atTime:kCMTimeZero];
        instruction.layerInstructions = [NSArray arrayWithObject: transformer];
        videoComposition.instructions = [NSArray arrayWithObject: instruction];
        
        
        // Audio
        AVAssetTrack *audioTrack;
        NSArray *tracks = [videoAsset tracksWithMediaType:AVMediaTypeAudio];
        if (tracks.count == 0) {
            AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:_audioURL options:nil];
            audioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        }else{
            audioTrack = [[videoAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        }
        
        AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        [compositionAudioTrack insertTimeRange:timeRange
                                       ofTrack:audioTrack
                                        atTime:kCMTimeZero
                                         error:nil];
        /*
        // Audioの合成パラメータオブジェクトを生成
        AVMutableAudioMixInputParameters *audioMixInputParameters;
        audioMixInputParameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
        [audioMixInputParameters setVolumeRampFromStartVolume:1.0
                                                  toEndVolume:1.0
                                                    timeRange:CMTimeRangeMake(kCMTimeZero, composition.duration)];
        
        // AVMutableAudioMixを生成
        AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
        audioMix.inputParameters = @[audioMixInputParameters];
        */
        
        // export
        AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality] ;
        exporter.videoComposition = videoComposition;
        //exporter.audioMix = audioMix;
        exporter.outputURL = outputURL;
        exporter.outputFileType = AVFileTypeQuickTimeMovie;
        
        [exporter exportAsynchronouslyWithCompletionHandler:^(void){
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusCompleted:
                    NSLog(@"Exporte completed!");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self.delegate respondsToSelector:@selector(cameraController:didFinishRecordingVideo:)]) {
                            [self.delegate cameraController:self didFinishRecordingVideo:outputURL];
                        }
                    });
                case AVAssetExportSessionStatusFailed:
                    NSLog(@"Export failed: %@", [[exportSession error] localizedDescription]);
                    break;
                case AVAssetExportSessionStatusCancelled:
                    NSLog(@"Export canceled");
                    break;
                default:
                    break;
            }

            _audioURL = nil;
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
    
    CFDictionaryRef metadata = CMCopyDictionaryOfAttachments(NULL, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    self.currentMetadata = ((__bridge_transfer NSDictionary *)metadata).mutableCopy;
    
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
