//
//  ViewController.h
//  eyedentify
//
//  Created by Michael Royzen on 1/14/17.
//  Copyright © 2017 The Three Bruhsketeers. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "OverlayViewController.h"
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Speech/Speech.h>
#import <GoogleMobileAds/GoogleMobileAds.h>
#import <Vision/Vision.h>
#import <CoreML/CoreML.h>
#import <MLKitTranslate/MLKitTranslate.h>

#import "MobileNetV2.h"
#import "Reachability.h"

@interface ViewController : UIViewController <AVSpeechSynthesizerDelegate, AVCapturePhotoCaptureDelegate, UIGestureRecognizerDelegate, SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate> {
}

@property(nonatomic, retain) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, retain) IBOutlet UIImageView *vImage;

@property (nonatomic) BOOL shouldRevert;
@property (strong, nonatomic) NSTimer *silenceTimer;
@property (strong, nonatomic) AVSpeechSynthesizer *synthesizer;

@property (strong, nonatomic) IBOutlet UILabel *recognizedObjectLabel;
@property (strong, nonatomic) IBOutlet UILabel *noCameraLabel;
@property (strong, nonatomic) IBOutlet UIView *cameraView;

@property (strong, nonatomic) SFSpeechRecognizer *recognizer;
@property (strong, nonatomic) SFSpeechAudioBufferRecognitionRequest *request;
@property (strong, nonatomic) SFSpeechRecognitionTask *recognitionTask;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@property (strong, nonatomic) VNCoreMLRequest *classificationRequest;
@property (strong, nonatomic) Reachability *reachability;
@property (strong, nonatomic) MLKModelManager *mlModelManager;
@property (strong, nonatomic) UIActivityIndicatorView *neuralNetActivityIndicator;

@end

