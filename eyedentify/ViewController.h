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
#import <SpeechKit/SpeechKit.h>
#import "eyedentify-Swift.h"
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "FGTranslator.h"
#import "AFNetworking.h"
#import "KVNProgress.h"

@interface ViewController : UIViewController <AVSpeechSynthesizerDelegate, SpeechKitDelegate, SKRecognizerDelegate> {
    SKRecognizer *voiceSearch;
    enum {
        TS_IDLE,
        TS_INITIAL,
        TS_RECORDING,
        TS_PROCESSING,
    } transactionState;
}

@property(nonatomic, retain) AVCaptureStillImageOutput *stillImageOutput;
@property(nonatomic, retain) IBOutlet UIImageView *vImage;
@property (strong, nonatomic) IBOutlet UIButton *fullScreenButton;
@property (nonatomic) BOOL shouldRevert;
@property (strong, nonatomic) IBOutlet UILabel *recognizedObjectLabel;

@end

