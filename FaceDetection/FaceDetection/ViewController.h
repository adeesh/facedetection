//
//  ViewController.h
//  FaceDetection
//
//  Created by Demansol on 17/08/15.
//  Copyright (c) 2015 Demansol. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController : UIViewController
<UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>{
    
}
/**
 *  This method initiate the real-time video capture and face detection. 
 */
- (void)setupAVCaptureSession;


@end
