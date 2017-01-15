//
//  ViewController.m
//  eyedentify
//
//  Created by Michael Royzen on 1/14/17.
//  Copyright © 2017 The Three Bruhsketeers. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () {
    dispatch_group_t group;
    AVSpeechSynthesizer *synthesizer;
    NSString *recognizedText;
    OverlayViewController *overlayViewController;
    NSString *recognitionLanguage;
    
    Inception3Net *Net;
    id <MTLDevice> device;
    id <MTLCommandQueue> commandQueue;
    int imageNum;
    int total;
    MTKTextureLoader *textureLoader;
    CIContext *ciContext;
    id <MTLTexture> sourceTexture;
    
    NSString *neuralNetworkResult;
    BOOL isRecognizing;

    AVCaptureDevice *captureDevice;
    UIView *cameraView;
    UIPinchGestureRecognizer *pinchRecognizer;
}

@end

const unsigned char SpeechKitApplicationKey[] = {0x41, 0x12, 0xd5, 0x4d, 0xbb, 0x61, 0xc1, 0x0f, 0x30, 0x0a, 0xde, 0xd8, 0x49, 0xe6, 0x27, 0xb9, 0x60, 0x81, 0xad, 0x49, 0x3f, 0x7f, 0x5e, 0x8e, 0xe5, 0x16, 0xa1, 0x8b, 0xa9, 0x3b, 0x3f, 0xea, 0x4d, 0x14, 0x37, 0x08, 0x75, 0xf8, 0x18, 0xa5, 0x02, 0xf6, 0x7d, 0x4c, 0xdc, 0xa5, 0x05, 0x3c, 0x26, 0xb2, 0x85, 0x65, 0x31, 0xe3, 0xf3, 0x17, 0xf9, 0x95, 0xa2, 0xa2, 0xd0, 0xe1, 0x8c, 0x1e};

@implementation ViewController
@synthesize stillImageOutput;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [SpeechKit setupWithID:@"NMDPPRODUCTION_Michael_Royzen_Readr_20150405205027"
                      host:@"dhw.nmdp.nuancemobility.net"
                      port:443
                    useSSL:YES
                  delegate:nil];
    
    device = MTLCreateSystemDefaultDevice();
    
    commandQueue = [device newCommandQueue];
    
    textureLoader = [[MTKTextureLoader alloc]initWithDevice:device];
    
    Net = [[Inception3Net alloc]initWithCommandQueue:commandQueue];
    
    ciContext = [CIContext contextWithMTLDevice:device];
    
    AVCaptureSession *captureSession = [AVCaptureSession new];
    captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    AVCaptureDeviceInput *cameraInput = [[AVCaptureDeviceInput alloc]initWithDevice:captureDevice error:&error];
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    self.shouldRevert = NO;
    
    stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
    [stillImageOutput setOutputSettings:outputSettings];
    
    [captureSession addInput:cameraInput];
    [captureSession addOutput:stillImageOutput];
    [captureSession startRunning];
    
    cameraView = [[UIView alloc]initWithFrame:self.view.frame];
    previewLayer.frame = cameraView.bounds;
    [cameraView.layer addSublayer:previewLayer];
    
    [self.view addSubview:cameraView];
    
    self.vImage = [[UIImageView alloc]init];
    
    overlayViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"OverlayViewController"];
    [self.view addSubview:overlayViewController.view];
    
    [self.view addSubview:self.fullScreenButton];
    
    recognitionLanguage = @"English";
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    synthesizer = [[AVSpeechSynthesizer alloc]init];
    [synthesizer setDelegate:self];
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"Welcome to eyedentify."];
    [utterance setRate:.5];
    [synthesizer speakUtterance:utterance];
    
    pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoomRecognizer:)];
    [self.view addGestureRecognizer:pinchRecognizer];
    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)recognizerDidBeginRecording:(SKRecognizer *)recognizer {
    NSLog(@"Recording started");
    transactionState = TS_RECORDING;
    //[KVNProgress showSuccessWithStatus:@"Began Listening"];
}

- (void)recognizerDidFinishRecording:(SKRecognizer *)recognizer {
    NSLog(@"Recording finished");
    transactionState = TS_PROCESSING;
}

- (void)recognizer:(SKRecognizer *)recognizer didFinishWithResults:(SKRecognition *)results {
    NSLog(@"Got results");
    NSLog(@"Session ID: [%@].", [SpeechKit sessionID]);
    
    isRecognizing = YES;
    [KVNProgress showWithStatus:@"Recognizing..."];
    
    recognizedText = [results firstResult];
    NSLog(@"Recognized text: %@", recognizedText);
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    if ([recognizedText containsString:@"in French"]) {
        recognitionLanguage = @"French";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"in Spanish"]) {
        recognitionLanguage = @"Spanish";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"in Russian"]) {
        recognitionLanguage = @"Russian";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"in English"]) {
        recognitionLanguage = @"English";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"am I looking at now"] || [recognizedText containsString:@"hat is this now"]) {
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"am I looking at"] || [recognizedText containsString:@"hat is this"]) {
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else {
        //restart speech recognition
        [self performSelector:@selector(beginSpeechRecognition) withObject:nil afterDelay:0.01];
    }
}

- (void)recognizer:(SKRecognizer *)recognizer didFinishWithError:(NSError *)error suggestion:(NSString *)suggestion {

}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)returnSynthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (isRecognizing == YES) {
        
        if ([recognitionLanguage isEqualToString:@"French"]) {
            //Translate to French
            //Speak in French
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"fr" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"fr-FR"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"Spanish"]) {
            //Speak in Spanish
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"es" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"Russian"]) {
            //Speak in Russian
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"ru" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"ru-RU"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"English"]) {
            [self beginSpeechRecognition];
        }
        isRecognizing = NO;
    }
    else {
        NSLog(@"Restart called");
        //re-start the recognition
        [self beginSpeechRecognition];
    }
}

- (void)runNeuralNet {
    //Run network
    
    struct CGImage *cgImg = [self.vImage.image CGImage];
    
    sourceTexture = [textureLoader newTextureWithCGImage:cgImg options:nil error:nil];
    
    @autoreleasepool {
        id <MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        [Net forwardWithCommandBuffer:commandBuffer sourceTexture:sourceTexture];
        
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        
        NSString *labelString = [Net getLabel];
        
        //extract top result from neural net results
        //neuralNetworkResult = [[labelString componentsSeparatedByString:@"/n"] objectAtIndex:0];
        __block NSString *secondLine = nil;
        __block int counter = 0;
        [labelString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            secondLine = line;
            if (counter == 1) {
                *stop = YES;
            }
            counter++;
        }];
        secondLine = [[secondLine componentsSeparatedByString:@", "] objectAtIndex:0];
        neuralNetworkResult = secondLine;
        NSLog(@"Result: %@", secondLine);
        [self speakResults];
    }
}

- (void)speakResults {
    //speak results
    
    if ([recognitionLanguage isEqualToString:@"English"]) {
        //Speak in English
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        NSString *stringToSpeak = [@"You are looking at a " stringByAppendingString:neuralNetworkResult];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:stringToSpeak];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"French"]) {
        //Speak in French
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Spanish"]) {
        //Speak in Spanish
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Russian"]) {
        //Speak in Russian
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
}

- (void)grabFrameFromVideo {
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in stillImageOutput.connections)
    {
        for (AVCaptureInputPort *port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] )
            {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) { break; }
    }
    
    NSLog(@"about to request a capture from: %@", stillImageOutput);
    dispatch_group_enter(group);
    [stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         CFDictionaryRef exifAttachments = CMGetAttachment( imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
         if (exifAttachments)
         {
             // Do something with the attachments.
             NSLog(@"attachements: %@", exifAttachments);
         }
         else
             NSLog(@"no attachments");
         
         NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
         UIImage *image = [[UIImage alloc] initWithData:imageData];
         
         self.vImage.image = image;
         dispatch_group_leave(group);
     }];
}

- (void)beginSpeechRecognition {
    voiceSearch = nil;
    SKEndOfSpeechDetection detectionType;
    NSString* recoType;
    
    //transactionState = TS_INITIAL;
    
    detectionType = SKLongEndOfSpeechDetection;
    recoType = SKDictationRecognizerType;
    
    voiceSearch = [[SKRecognizer alloc] initWithType:recoType
                                           detection:detectionType
                                            language:@"en_US"
                                            delegate:self];
}

- (void)handlePinchToZoomRecognizer:(UIPinchGestureRecognizer *)pinchRecognizer {
    NSLog(@"The view should start zooming");
    const CGFloat pinchVelocityDividerFactor = 5.0f;
    
    if (pinchRecognizer.state == UIGestureRecognizerStateChanged) {
        NSError *error = nil;
        if ([captureDevice lockForConfiguration:&error]) {
            CGFloat desiredZoomFactor = captureDevice.videoZoomFactor + atan2f(pinchRecognizer.velocity, pinchVelocityDividerFactor);
            captureDevice.videoZoomFactor = MAX(1.0, MIN(desiredZoomFactor, captureDevice.activeFormat.videoMaxZoomFactor));
            [captureDevice unlockForConfiguration];
        } else {
            NSLog(@"Oh shit an error occurred: %@", error);
        }
    }
}

- (IBAction)fullScreenPressed:(UIButton *)sender {
    if (self.shouldRevert == NO) {
        [sender setTitle:@"Revert" forState:UIControlStateNormal];
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                overlayViewController.logoView.frame = CGRectMake(overlayViewController.logoView.frame.origin.x, overlayViewController.logoView.frame.origin.y - 400, overlayViewController.logoView.frame.size.width,
                                                                  overlayViewController.logoView.frame.size.height);
                overlayViewController.suggestionView.frame = CGRectMake(overlayViewController.suggestionView.frame.origin.x, overlayViewController.suggestionView.frame.origin.y - 600, overlayViewController.suggestionView.frame.size.width,
                                                                        overlayViewController.suggestionView.frame.size.height);
            } completion:^(BOOL finished) {
                NSLog(@"The animation finished.");
                self.shouldRevert = YES;
            }];
        });
    } else if (self.shouldRevert == YES) {
        [sender setTitle:@"Full Screen" forState:UIControlStateNormal];
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                overlayViewController.logoView.frame = CGRectMake(37, 50, overlayViewController.logoView.frame.size.width,
                                                                  overlayViewController.logoView.frame.size.height);
                overlayViewController.suggestionView.frame = CGRectMake(37, 377, overlayViewController.suggestionView.frame.size.width, overlayViewController.suggestionView.frame.size.height);
            } completion:^(BOOL finished) {
                NSLog(@"The second animation finished.");
                self.shouldRevert = NO;
            }];
        });
    }
}

@end
