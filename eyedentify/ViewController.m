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
    BOOL touchesActive;

    AVCaptureDevice *captureDevice;
    UIView *cameraView;
    UIPinchGestureRecognizer *pinchRecognizer;
    UITapGestureRecognizer *tapGestureRecognizer;
    BOOL isRecording;
}

@end

const unsigned char SpeechKitApplicationKey[] = {0x41, 0x12, 0xd5, 0x4d, 0xbb, 0x61, 0xc1, 0x0f, 0x30, 0x0a, 0xde, 0xd8, 0x49, 0xe6, 0x27, 0xb9, 0x60, 0x81, 0xad, 0x49, 0x3f, 0x7f, 0x5e, 0x8e, 0xe5, 0x16, 0xa1, 0x8b, 0xa9, 0x3b, 0x3f, 0xea, 0x4d, 0x14, 0x37, 0x08, 0x75, 0xf8, 0x18, 0xa5, 0x02, 0xf6, 0x7d, 0x4c, 0xdc, 0xa5, 0x05, 0x3c, 0x26, 0xb2, 0x85, 0x65, 0x31, 0xe3, 0xf3, 0x17, 0xf9, 0x95, 0xa2, 0xa2, 0xd0, 0xe1, 0x8c, 0x1e};

@implementation ViewController
@synthesize stillImageOutput;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    //Initialize speech recognition framework
    
    [SpeechKit setupWithID:@"NMDPPRODUCTION_Michael_Royzen_Readr_20150405205027"
                      host:@"dhw.nmdp.nuancemobility.net"
                      port:443
                    useSSL:YES
                  delegate:nil];
    
    //Initialize Metal and neural net
    
    device = MTLCreateSystemDefaultDevice();
    
    commandQueue = [device newCommandQueue];
    
    textureLoader = [[MTKTextureLoader alloc]initWithDevice:device];
    
    Net = [[Inception3Net alloc]initWithCommandQueue:commandQueue];
    
    ciContext = [CIContext contextWithMTLDevice:device];
    
    //Initialize live camera preview
    
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
    
    //Add live camera preview as a subview
    
    cameraView = [[UIView alloc]initWithFrame:self.view.frame];
    previewLayer.frame = cameraView.bounds;
    [cameraView.layer addSublayer:previewLayer];
    
    [self.view addSubview:cameraView];
    
    self.vImage = [[UIImageView alloc]init];
    
    //Initialize and add the graphical overlay as a subview
    
    overlayViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"OverlayViewController"];
    [self.view addSubview:overlayViewController.view];
    
    [self.view addSubview:self.fullScreenButton];
    
    recognitionLanguage = @"English";
    
    //Init speech synthesizer and gesture recognizers
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    synthesizer = [[AVSpeechSynthesizer alloc]init];
    [synthesizer setDelegate:self];
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"Welcome to eyedentify.  After the vibration, please say a command or tap the screen ."];
    [utterance setRate:.5];
    [synthesizer speakUtterance:utterance];
    
    [self.view addSubview:self.recognizedObjectLabel];
    
    pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoomRecognizer:)];
    [self.view addGestureRecognizer:pinchRecognizer];
    
    tapGestureRecognizer = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleTap)];
    [tapGestureRecognizer setDelegate:self];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    touchesActive = NO;
    
    isRecording = NO;
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)recognizerDidBeginRecording:(SKRecognizer *)recognizer {
    NSLog(@"Recording started");
    transactionState = TS_RECORDING;
    
    isRecording = YES;
    //[KVNProgress showSuccessWithStatus:@"Began Listening"];
}

- (void)handleTap {
    [voiceSearch stopRecording];
    isRecognizing = YES;
    touchesActive = YES;
     
    group = dispatch_group_create();
    [self grabFrameFromVideo];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        //Grab still frame from video and run neural net once that completes
        [self runNeuralNet];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    //Prevent unwanted touches from being proccessed
    
    if ([touch view] == self.fullScreenButton || isRecording == NO){
        // If it is, prevent all of the delegate's gesture recognizers
        // from receiving the touch
        return NO;
    }
    return YES;
}

- (void)recognizerDidFinishRecording:(SKRecognizer *)recognizer {
    NSLog(@"Recording finished");
    transactionState = TS_PROCESSING;
    
    isRecording = NO;
    //[KVNProgress showWithStatus:@"Processing..."];
}

- (void)recognizer:(SKRecognizer *)recognizer didFinishWithResults:(SKRecognition *)results {
    NSLog(@"Got results");
    NSLog(@"Session ID: [%@].", [SpeechKit sessionID]);
    
    //Process speech recognition results
    
    isRecognizing = YES;
    
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
    else if ([recognizedText containsString:@"in German"]) {
        recognitionLanguage = @"German";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"in Mandarin"]) {
        recognitionLanguage = @"Mandarin";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"in Italian"]) {
        recognitionLanguage = @"Italian";
        
        group = dispatch_group_create();
        [self grabFrameFromVideo];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self runNeuralNet];
        });
    }
    else if ([recognizedText containsString:@"am I looking at now"] || [recognizedText containsString:@"hat is this now"] || [recognizedText containsString:@"hat about now"] || [recognizedText containsString:@"And now"]) {
        
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
        if (touchesActive == NO) {
            [self performSelector:@selector(beginSpeechRecognition) withObject:nil afterDelay:0.01];
        }
    }
}

- (void)recognizer:(SKRecognizer *)recognizer didFinishWithError:(NSError *)error suggestion:(NSString *)suggestion {

}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    //[KVNProgress dismiss];
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
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
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
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
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
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"German"]) {
            //Speak in German
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"de" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"de-DE"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"Mandarin"]) {
            //Speak in Mandarin
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"zh-TW" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"zh-TW"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"Italian"]) {
            //Speak in Italian
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"it" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                synthesizer = [[AVSpeechSynthesizer alloc]init];
                [synthesizer setDelegate:self];
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"]];
                [utterance setRate:.5];
                [synthesizer speakUtterance:utterance];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
            }];
        }
        else if ([recognitionLanguage isEqualToString:@"English"]) {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
            if (touchesActive == NO) {
                NSLog(@"Begun for english");
            }
            [self beginSpeechRecognition];
        }
        isRecognizing = NO;
        touchesActive = NO;
    }
    else {
        NSLog(@"Restart called");
        //Re-start speech recognition
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
        [self beginSpeechRecognition];
    }
}

- (void)hideLabel {
    self.recognizedObjectLabel.hidden = YES;
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
        dispatch_async(dispatch_get_main_queue(), ^{
            self.recognizedObjectLabel.text = neuralNetworkResult;
            self.recognizedObjectLabel.hidden = NO;
        });
        
        NSTimer *timer;
        timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
        
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
    else if ([recognitionLanguage isEqualToString:@"German"]) {
        //Speak in German
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Mandarin"]) {
        //Speak in Mandarin
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Italian"]) {
        //Speak in Italian
        synthesizer = [[AVSpeechSynthesizer alloc]init];
        [synthesizer setDelegate:self];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [synthesizer speakUtterance:utterance];
    }
}

- (void)grabFrameFromVideo {
    //Grab still frame from video stream and store it as a UIImage
    
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
    //Zoom camera view
    
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
    //Toggle full screen mode (graphical overlay is animated out of the view)
    
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
