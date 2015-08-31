//
//  ViewController.m
//  FaceDetection
//
//  Created by Demansol on 17/08/15.
//  Copyright (c) 2015 Demansol. All rights reserved.
//

#import "ViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIView *previewView;
/**
 *  Value of this property will be true if fron camera is being used as input device.
 */
@property (nonatomic) BOOL isUsingFrontCamera;
/**
 *  This property is used to process frames from the video being captured.
 */
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
/**
 *  Dispatch queues are lightweight objects to which blocks may be submitted.
 */
@property (nonatomic) dispatch_queue_t videoOutputQueue;
/**
 *  This property is used to preview capture session
 */
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

/**
 *  This property is used to detect faces in an image
 */
@property (nonatomic, strong) CIDetector *faceDetector;


- (void)cleareAVCaptureSession;
- (void)findFaces:(NSArray *)features forVideoBox:(CGRect)videoBox orientation:(UIDeviceOrientation)orientation;

@end

@implementation ViewController

@synthesize videoOutput = _videoOutput;
@synthesize videoOutputQueue = _videoOutputQueue;
@synthesize previewView = _previewView;
@synthesize previewLayer = _previewLayer;
@synthesize faceDetector = _faceDetector;
@synthesize isUsingFrontCamera = _isUsingFrontCamera;

- (void)setupAVCaptureSession
{
    NSError *error = nil;
    
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone){
        [captureSession setSessionPreset:AVCaptureSessionPreset640x480];
    } else {
        [captureSession setSessionPreset:AVCaptureSessionPresetPhoto];
    }
    [captureSession setSessionPreset:AVCaptureSessionPresetMedium];
    AVCaptureDevice *device;
    for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([d position] == AVCaptureDevicePositionFront) {
            device = d;
            self.isUsingFrontCamera = YES;
            break;
        }
    }
    if( nil == device )
    {
        self.isUsingFrontCamera = NO;
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if( !error ) {
        
        
        if ( [captureSession canAddInput:deviceInput] ){
            [captureSession addInput:deviceInput];
        }
        
        
        self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        
        NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                           [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [self.videoOutput setVideoSettings:rgbOutputSettings];
        [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];
        
        
        self.videoOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
        [self.videoOutput setSampleBufferDelegate:self queue:self.videoOutputQueue];
        
        if ( [captureSession canAddOutput:self.videoOutput] ){
            [captureSession addOutput:self.videoOutput];
        }
        
        
        AVCaptureConnection* captureConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        captureConnection.enabled = YES;
        
        self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
        self.previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        CALayer *rootLayer = [self.previewView layer];
        [rootLayer setMasksToBounds:YES];
        [self.previewLayer setFrame:[rootLayer bounds]];
        [rootLayer addSublayer:self.previewLayer];
        
        /*
        if([device isTorchModeSupported:AVCaptureTorchModeOn]) {
            [device lockForConfiguration:nil];
            [device setActiveVideoMaxFrameDuration:CMTimeMake(1,10)];
            [device setActiveVideoMinFrameDuration:CMTimeMake(1, 10)];
            [device unlockForConfiguration];
        }
         */
        
        [captureSession startRunning];
        
        NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
        self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
        
    }
    captureSession = nil;
    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:
                                  [NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                                            message:[error localizedDescription]
                                                           delegate:nil
                                                  cancelButtonTitle:@"Dismiss"
                                                  otherButtonTitles:nil];
        [alertView show];
        [self cleareAVCaptureSession];
    }
}
/**
 *  Remove the AVCaptureVideoPreviewLayer.
 */
- (void)cleareAVCaptureSession
{
    self.videoOutput = nil;
    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
}
/**
 *  Find where the video box is positioned within the AVCaptureVideoPreviewLayer  based on the video size and gravity
 *
 *  @param gravity      String that represents videoGravity of the  AVCaptureVideoPreviewLayer
 *  @param frameSize    frame size of AVCaptureVideoPreviewLayer's parent view
 *  @param apertureSize size of the rectangle for clean aperture
 *
 *  @return rectangle within the AVCaptureVideoPreviewLayer
 */
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity
                          frameSize:(CGSize)frameSize
                       apertureSize:(CGSize)apertureSize
{
    
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
    
    CGRect videoBox;
    videoBox.size = size;
    if (size.width < frameSize.width)
        videoBox.origin.x = (frameSize.width - size.width) / 2;
    else
        videoBox.origin.x = (size.width - frameSize.width) / 2;
    
    if ( size.height < frameSize.height )
        videoBox.origin.y = (frameSize.height - size.height) / 2;
    else
        videoBox.origin.y = (size.height - frameSize.height) / 2;
    
    return videoBox;
}
/**
 *  Detect faces as rectangle and place a CSLayer there
 *
 *  @param features      array of CIFaceFeature
 *  @param clearAperture size of the rectangle for clean aperture
 *  @param orientation   current device orientation
 */
- (void)findFaces:(NSArray *)features
      forVideoBox:(CGRect)clearAperture
      orientation:(UIDeviceOrientation)orientation
{
    NSArray *sublayers = [NSArray arrayWithArray:[self.previewLayer sublayers]];
    NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
    NSInteger featuresCount = [features count], currentFeature = 0;
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    
    for ( CALayer *layer in sublayers ) {
        if ( [[layer name] isEqualToString:@"FaceLayer"] )
            [layer setHidden:YES];
    }
    
    if ( featuresCount == 0 ) {
        [CATransaction commit];
        return;
    }
    
    CGSize parentFrameSize = [self.previewView frame].size;
    NSString *gravity = [self.previewLayer videoGravity];
    BOOL isMirrored = [self.previewLayer isMirrored];
    CGRect previewBox = [ViewController videoPreviewBoxForGravity:gravity
                                                        frameSize:parentFrameSize
                                                     apertureSize:clearAperture.size];
    
    for ( CIFaceFeature *ff in features ) {
        CGRect faceRect = [ff bounds];
        CGFloat temp = faceRect.size.width;
        faceRect.size.width = faceRect.size.height;
        faceRect.size.height = temp;
        temp = faceRect.origin.x;
        faceRect.origin.x = faceRect.origin.y;
        faceRect.origin.y = temp;
        CGFloat widthScaleBy = previewBox.size.width / clearAperture.size.height;
        CGFloat heightScaleBy = previewBox.size.height / clearAperture.size.width;
        faceRect.size.width *= widthScaleBy;
        faceRect.size.height *= heightScaleBy;
        faceRect.origin.x *= widthScaleBy;
        faceRect.origin.y *= heightScaleBy;
        
        if ( isMirrored )
            faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
        else
            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
        
        CALayer *featureLayer = nil;
        
        
        while ( !featureLayer && (currentSublayer < sublayersCount) ) {
            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
            if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
                featureLayer = currentLayer;
                [currentLayer setHidden:NO];
            }
        }
        
       
        if ( !featureLayer ) {
            featureLayer = [[CALayer alloc]init];
            featureLayer.backgroundColor = [[UIColor greenColor] CGColor];
            [featureLayer setName:@"FaceLayer"];
            [self.previewLayer addSublayer:featureLayer];
            featureLayer = nil;
        }
        [featureLayer setFrame:faceRect];
        
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
                break;
            case UIDeviceOrientationLandscapeLeft:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
                break;
            case UIDeviceOrientationLandscapeRight:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
                break;
            case UIDeviceOrientationFaceUp:
            case UIDeviceOrientationFaceDown:
            default:
                break;
        }
        currentFeature++;
        
    }
    
    [CATransaction commit];
}

/**
 *  returns an NSNumber based on the current device orientation and input device(i.e. front or back camera) 
 *
 *  @param orientation current device orientation
 *
 *  @return returns NSNumber
 */
- (NSNumber *) exifOrientation: (UIDeviceOrientation) orientation
{
    int exifOrientation;
    
    enum {
        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1,
        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2,
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3,
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4,
        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5,
        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6,
        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7,
        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8
    };
    
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
            break;
        case UIDeviceOrientationLandscapeLeft:
            if (self.isUsingFrontCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            break;
        case UIDeviceOrientationLandscapeRight:
            if (self.isUsingFrontCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            break;
        case UIDeviceOrientationPortrait:
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
            break;
    }
    return [NSNumber numberWithInt:exifOrientation];
}

//AVCaptureVideoDataOutputSampleBufferDelegate method
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer
                                                      options:(__bridge NSDictionary *)attachments];
    if (attachments) {
        CFRelease(attachments);
    }
    
    
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    
    NSDictionary *imageOptions = nil;
    
    imageOptions = [NSDictionary dictionaryWithObject:[self exifOrientation:curDeviceOrientation]
                                               forKey:CIDetectorImageOrientation];
    
    NSArray *features = [self.faceDetector featuresInImage:ciImage
                                                   options:imageOptions];
    
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc, false );
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self findFaces:features 
            forVideoBox:cleanAperture 
            orientation:curDeviceOrientation];
    });
}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
    [self setupAVCaptureSession];
    
}
- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [self cleareAVCaptureSession];
    self.faceDetector = nil;
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
