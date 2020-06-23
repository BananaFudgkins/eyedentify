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
    NSString *recognizedText;
    NSString *recognitionLanguage;
    
    // Old neural net stuff.
    
    /* Inception3Net *Net;
    id <MTLDevice> device;
    id <MTLCommandQueue> commandQueue;
    int imageNum;
    int total;
    MTKTextureLoader *textureLoader;
    CIContext *ciContext;
    id <MTLTexture> sourceTexture; */
    
    NSString *neuralNetworkResult;
    BOOL isRecognizing;
    BOOL touchesActive;

    AVCaptureDevice *captureDevice;
    UIPinchGestureRecognizer *pinchRecognizer;
    UITapGestureRecognizer *tapGestureRecognizer;
    AVAudioInputNode *inputNode;
    BOOL isRecording;
    
    AVCaptureSession *captureSession;
}

@end

@implementation ViewController
@synthesize photoOutput;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.audioEngine = [[AVAudioEngine alloc] init];
    self.mlModelManager = [MLKModelManager modelManager];
    
    self.neuralNetActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.neuralNetActivityIndicator.center = self.view.center;
    self.neuralNetActivityIndicator.hidden = YES;
    
    // Do any additional setup after loading the view, typically from a nib.
    
#ifdef DEBUG
    self.adBannerView.adUnitID = @"ca-app-pub-3940256099942544/2934735716"; // Unit ID is for debug. Change for release and vice versa.
#else
    self.adBannerView.adUnitID = @"ca-app-pub-4329905567201043/8988070404"; // Unit ID for release.
#endif
    
    [self.adBannerView loadRequest:[GADRequest request]];
}

- (void)setupCameraPreview {
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession beginConfiguration];
    
    captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    AVCaptureDeviceInput *cameraInput = [[AVCaptureDeviceInput alloc]initWithDevice:captureDevice error:&error];
    self.shouldRevert = NO;
    
    //Add live camera preview as a subview, though only if the camera is supported
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        photoOutput = [[AVCapturePhotoOutput alloc] init];
        
        [captureSession addInput:cameraInput];
        
        captureSession.sessionPreset = AVCaptureSessionPreset640x480;
        [captureSession addOutput:photoOutput];
        
        AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        previewLayer.frame = CGRectMake(0,
                                        0,
                                        self.view.bounds.size.width,
                                        self.view.bounds.size.height - self.adBannerView.bounds.size.height);
        
        [captureSession commitConfiguration];
        [captureSession startRunning];
        
        [self.view.layer insertSublayer:previewLayer atIndex:0];
        [self.view addSubview:self.neuralNetActivityIndicator];
        [self checkSpeechRecognitionPermission];
    } else {
        self.noCameraLabel.hidden = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    //Initialize Metal and neural net
    
    /* device = MTLCreateSystemDefaultDevice();
    
    commandQueue = [device newCommandQueue];
    
    textureLoader = [[MTKTextureLoader alloc] initWithDevice:device];
    
    Net = [[Inception3Net alloc] initWithCommandQueue:commandQueue];
    
    ciContext = [CIContext contextWithMTLDevice:device]; */
    
    SqueezeNet *squeezeNet = [[SqueezeNet alloc] init];
    VNCoreMLModel *model = [VNCoreMLModel modelForMLModel:squeezeNet.model error:nil];
    self.classificationRequest = [[VNCoreMLRequest alloc] initWithModel:model completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        if (!error) {
            [self processClassificationsForRequest:request error:error];
        }
    }];
    
    self.vImage = [[UIImageView alloc] init];
    
    self.reachability = [Reachability reachabilityForInternetConnection];
    [self.reachability startNotifier];
    
    recognitionLanguage = @"English";
    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    self.recognizer.delegate = self;
    
    //Init speech synthesizer and gesture recognizers
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    self.synthesizer = [[AVSpeechSynthesizer alloc] init];
    self.synthesizer.delegate = self;
    
    //Initialize live camera preview
    
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized) {
        [self setupCameraPreview];
    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Welcome to Eyedentify. Before you can begin using the app, please grant access to your camera so you can take pictures of the objects around you."];
        utterance.rate = 0.5;
        
        [self.synthesizer speakUtterance:utterance];
        
        touchesActive = NO;
        
        isRecording = NO;
    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusDenied || [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusRestricted) {
        AVSpeechSynthesizer *uhOhSynth = [[AVSpeechSynthesizer alloc] init];
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Welcome to Eyedentify. You have denied or restricted access to your device's camera. You will not be able to use the app before you grant permission."];
        utterance.rate = 0.5;
        
        [uhOhSynth speakUtterance:utterance];
        
        touchesActive = NO;
        
        isRecording = NO;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)checkSpeechRecognitionPermission {
    if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
            AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:@"Welcome to eyedentify.  After the vibration, please say a command or tap the screen ."];
            [utterance setRate:.5];
            [self.synthesizer speakUtterance:utterance];
            
            tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
            tapGestureRecognizer.delegate = self;
            [self.view addGestureRecognizer:tapGestureRecognizer];
            
            pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoomRecognizer:)];
            [self.view addGestureRecognizer:pinchRecognizer];
            
            touchesActive = NO;
            
            isRecording = NO;
        } else if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionUndetermined) {
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Welcome to eyedentify. Before you can begin using the app, please grant access to your device's microphone."];
            utterance.rate = 0.5;
            
            [self.synthesizer speakUtterance:utterance];
            
            touchesActive = NO;
            
            isRecording = NO;
        }
        
    } else if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:@"Welcome to eyedentify. Before you can begin using the app, please grant access to speech recognition."];
        [utterance setRate:0.5];
        [self.synthesizer speakUtterance:utterance];
        
        touchesActive = NO;
        
        isRecording = NO;
    } else if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusDenied || [SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusRestricted) {
        AVSpeechSynthesizer *uhOhSynth = [[AVSpeechSynthesizer alloc] init];
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"You have denied or restricted access to speech recognition. Please grant permission in Settings and try again."];
        utterance.rate = 0.5;
        
        [uhOhSynth speakUtterance:utterance];
        [captureSession stopRunning];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    NSLog(@"The screen was tapped");
    
    /* [inputNode removeTapOnBus:0];
    [self.recognitionTask cancel];
    self.recognitionTask = nil; */
    
    isRecognizing = YES;
    touchesActive = YES;
     
    group = dispatch_group_create();
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self grabFrameFromVideo];
    });
    /* dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        //Grab still frame from video and run neural net once that completes
        [self runNeuralNet];
    }); */
}

- (void)handlePinchToZoomRecognizer:(UIPinchGestureRecognizer *)pinchRecognizer {
    //Zoom camera view
    
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

/* - (void)handleTap {
    NSLog(@"The screen was tapped");
    
    [inputNode removeTapOnBus:0];
    [_recognitionTask cancel];
    _recognitionTask = nil;
    
    if (transactionState == TS_RECORDING) {
        [voiceSearch stopRecording];
    }
    
    isRecognizing = YES;
    touchesActive = YES;
     
    group = dispatch_group_create();
    [self grabFrameFromVideo];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        //Grab still frame from video and run neural net once that completes
        [self runNeuralNet];
    });
} */

#pragma mark - Touch recognizer delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    //Prevent unwanted touches from being proccessed
    
    if (isRecording == NO){
        // If it is, prevent all of the delegate's gesture recognizers
        // from receiving the touch
        NSLog(@"The screen should not be taking any more touches.");
        return NO;
    }
    return YES;
}

#pragma mark - Speech synthesizer delegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    [[AVAudioSession sharedInstance] setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    //[KVNProgress dismiss];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)returnSynthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    
    if (isRecognizing == YES) {
        
        /* if ([recognitionLanguage isEqualToString:@"French"]) {
            //Translate to French
            //Speak in French
            FGTranslator *translator =
            [[FGTranslator alloc]initWithGoogleAPIKey:@"AIzaSyDOpsPt1JdWFaC_SrxToRd3oLPvJwixjIo"];
            
            [translator translateText:neuralNetworkResult withSource:@"en" target:@"fr" completion:^(NSError *error, NSString *translated, NSString *sourceLanguage) {
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"fr-FR"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
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
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
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
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"ru-RU"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
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
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"de-DE"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
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
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"zh-TW"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
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
                AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:translated];
                [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"]];
                [utterance setRate:.5];
                [self.synthesizer speakUtterance:utterance];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.recognizedObjectLabel.text = translated;
                    self.recognizedObjectLabel.hidden = NO;
                });
                
                NSTimer *timer;
                timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
            }];
        } */
        if ([recognitionLanguage isEqualToString:@"French"]) {
            MLKTranslatorOptions *options = [[MLKTranslatorOptions alloc] initWithSourceLanguage:MLKTranslateLanguageEnglish
                                                                                  targetLanguage:MLKTranslateLanguageFrench];
            MLKTranslator *translator = [MLKTranslator translatorWithOptions:options];
            
            if (self.reachability.currentReachabilityStatus == ReachableViaWiFi) {
                if (![self.mlModelManager.downloadedTranslateModels containsObject:[MLKTranslateRemoteModel translateRemoteModelWithLanguage:MLKTranslateLanguageFrench]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.recognizedObjectLabel.text = @"Downloading translations...";
                        self.recognizedObjectLabel.hidden = NO;
                    });
                    
                    MLKModelDownloadConditions *conditions = [[MLKModelDownloadConditions alloc] initWithAllowsCellularAccess:NO
                                                                                                  allowsBackgroundDownloading:YES];
                    [translator downloadModelIfNeededWithConditions:conditions completion:^(NSError * _Nullable error) {
                        if (!error) {
                            [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                                if (result) {
                                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                                    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"fr-FR"];
                                    utterance.rate = 0.5;
                                    
                                    isRecognizing = NO;
                                    [self.synthesizer speakUtterance:utterance];
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        self.recognizedObjectLabel.text = result;
                                    });
                                    
                                    NSTimer *timer;
                                    timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                                }
                            }];
                        } else {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to download translations. Please check your internet connection and try again."];
                            utterance.rate = 0.5;
                            
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }];
                } else {
                    [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                        if (result) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"fr-FR"];
                            utterance.rate = 0.5;
                            
                            isRecognizing = NO;
                            [self.synthesizer speakUtterance:utterance];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self.recognizedObjectLabel.text = result;
                                self.recognizedObjectLabel.hidden = NO;
                            });
                            
                            NSTimer *timer;
                            timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                        }
                    }];
                }
            } else if (self.reachability.currentReachabilityStatus == ReachableViaWWAN) {
                if ([self.mlModelManager.downloadedTranslateModels containsObject:[MLKTranslateRemoteModel translateRemoteModelWithLanguage:MLKTranslateLanguageFrench]]) {
                    [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                        if (result) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"fr-FR"];
                            utterance.rate = 0.5;
                            
                            isRecognizing = NO;
                            [self.synthesizer speakUtterance:utterance];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self.recognizedObjectLabel.text = result;
                                self.recognizedObjectLabel.hidden = NO;
                            });
                            
                            NSTimer *timer;
                            timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                        } else {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to translate. Please try again."];
                            utterance.rate = 0.5;
                            
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }];
                } else {
                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Please connect to WiFi to download translations and try again."];
                    utterance.rate = 0.5;
                    
                    [self.synthesizer speakUtterance:utterance];
                }
            }
            
            // For now, just download the model. Hopefully the user can tolerate waiting for a bit longer.
            
        }
        else if ([recognitionLanguage isEqualToString:@"Spanish"]) {
            MLKTranslatorOptions *options = [[MLKTranslatorOptions alloc] initWithSourceLanguage:MLKTranslateLanguageEnglish
                                                                                  targetLanguage:MLKTranslateLanguageSpanish];
            MLKTranslator *translator = [MLKTranslator translatorWithOptions:options];
            
            if (self.reachability.currentReachabilityStatus == ReachableViaWiFi) {
                if (![self.mlModelManager.downloadedTranslateModels containsObject:[MLKTranslateRemoteModel translateRemoteModelWithLanguage:MLKTranslateLanguageSpanish]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.recognizedObjectLabel.text = @"Downloading translations...";
                        self.recognizedObjectLabel.hidden = NO;
                    });
                    
                    MLKModelDownloadConditions *conditions = [[MLKModelDownloadConditions alloc] initWithAllowsCellularAccess:NO
                                                                                                  allowsBackgroundDownloading:YES];
                    [translator downloadModelIfNeededWithConditions:conditions completion:^(NSError * _Nullable error) {
                        if (!error) {
                            [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                                if (result) {
                                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                                    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"];
                                    utterance.rate = 0.5;
                                    
                                    isRecognizing = NO;
                                    [self.synthesizer speakUtterance:utterance];
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        self.recognizedObjectLabel.text = result;
                                    });
                                    
                                    NSTimer *timer;
                                    timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                                } else {
                                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to translate. Please try again."];
                                    utterance.rate = 0.5;
                                    
                                    [self.synthesizer speakUtterance:utterance];
                                }
                            }];
                        } else {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to download translations. Please check your internet connection and try again."];
                            utterance.rate = 0.5;
                            
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }];
                } else {
                    [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                        if (result) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"];
                            utterance.rate = 0.5;
                            
                            isRecognizing = NO;
                            [self.synthesizer speakUtterance:utterance];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self.recognizedObjectLabel.text = result;
                                self.recognizedObjectLabel.hidden = NO;
                            });
                            
                            NSTimer *timer;
                            timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                        } else {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to translate. Please try again."];
                            utterance.rate = 0.5;
                            
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }];
                }
            } else if (self.reachability.currentReachabilityStatus == ReachableViaWWAN) {
                if ([self.mlModelManager.downloadedTranslateModels containsObject:[MLKTranslateRemoteModel translateRemoteModelWithLanguage:MLKTranslateLanguageSpanish]]) {
                    [translator translateText:neuralNetworkResult completion:^(NSString * _Nullable result, NSError * _Nullable error) {
                        if (result) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:result];
                            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"es-ES"];
                            utterance.rate = 0.5;
                            
                            isRecognizing = NO;
                            [self.synthesizer speakUtterance:utterance];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self.recognizedObjectLabel.text = result;
                                self.recognizedObjectLabel.hidden = NO;
                            });
                            
                            NSTimer *timer;
                            timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
                        } else {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Something went wrong when trying to translate. Please try again."];
                            utterance.rate = 0.5;
                            
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }];
                } else {
                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Please connect to WiFi to download translations and try again."];
                    utterance.rate = 0.5;
                    
                    [self.synthesizer speakUtterance:utterance];
                }
            }
        }
        else if ([recognitionLanguage isEqualToString:@"English"]) {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
            if (touchesActive == NO) {
                NSLog(@"Begun for english");
            }
            /* if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
                [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                    if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
                        if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
                            [self performSelector:@selector(beginNativeSpeechRecognition) withObject:nil afterDelay:0.01];
                        } else if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionUndetermined) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"We also need access to your device's microphone. Please grant it now."];
                            utterance.rate = 0.5;
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }
                }];
            } */
        }
        isRecognizing = NO;
        touchesActive = NO;
    }
    else {
        NSLog(@"Restart called");
        //Re-start speech recognition
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
        if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Thank you for granting access to your device's camera. Next, please grant access to speech recognition."];
                    utterance.rate = 0.5;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setupCameraPreview];
                    });
                    
                    [self.synthesizer speakUtterance:utterance];
                }
            }];
        } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized) {
            if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
                NSLog(@"Asking for speech recognition permission...");
                [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                    if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
                        // isRecognizing = YES;
                        if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
                            AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:@"Thank you for granting access to speech recognition. After the vibration, please say a command or tap the screen."];
                            [self.synthesizer speakUtterance:utterance];
                            // [self performSelector:@selector(beginNativeSpeechRecognition) withObject:nil afterDelay:0.01];
                        } else if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionUndetermined) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"We also need access to your device's microphone. Please grant it now."];
                            utterance.rate = 0.5;
                            [self.synthesizer speakUtterance:utterance];
                        }
                    }
                }];
            } else if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized) {
                if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
                    NSLog(@"Access to the microphone, speech recognition, and the camera have been granted.");
                    [self performSelector:@selector(beginNativeSpeechRecognition) withObject:nil afterDelay:0.01];
                } else if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionUndetermined) {
                    NSLog(@"Asking for access to the microphone...");
                    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                        if (granted) {
                            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Thank you for granting access to your device's microphone. After the vibration, please say a command or tap the screen."];
                            utterance.rate = 0.5;
                            [self.synthesizer speakUtterance:utterance];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
                                tapGestureRecognizer.delegate = self;
                                [self.view addGestureRecognizer:tapGestureRecognizer];
                                
                                pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoomRecognizer:)];
                                [self.view addGestureRecognizer:pinchRecognizer];
                            });
                        }
                    }];
                }
            }
        }
    }
}

- (void)hideLabel {
    self.recognizedObjectLabel.hidden = YES;
}

- (void)runNeuralNet {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.neuralNetActivityIndicator startAnimating];
        self.neuralNetActivityIndicator.hidden = NO;
    });
    
    
    struct CGImage *cgImg = [self.vImage.image CGImage];
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImg options:nil];
    NSError *error;
    
    @try {
        NSLog(@"Putting out a request to the neural net...");
        [handler performRequests:@[self.classificationRequest] error:&error];
    } @catch (NSException *exception) {
        NSLog(@"Unable to classify image: %@", error.localizedDescription);
    }
}

- (void)processClassificationsForRequest:(VNCoreMLRequest *) request error:(NSError *)error {
    //Run network
    
    // Old neural net code.
    
    /* struct CGImage *cgImg = [self.vImage.image CGImage];

    sourceTexture = [textureLoader newTextureWithCGImage:cgImg options:@{MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModePrivate)} error:nil];
    NSLog(@"Texture storage mode: %lu", (unsigned long)sourceTexture.storageMode);
    
    
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
    } */
    
    NSLog(@"Processing neural net results...");
    if (request.results) {
        NSArray<VNClassificationObservation *> *classifications = request.results;
        if (classifications.count == 0) {
            NSLog(@"Nothing was recognized.");
        } else {
            VNClassificationObservation *top = classifications[0];
            neuralNetworkResult = top.identifier;
            NSLog(@"Result: %@", top.identifier);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.neuralNetActivityIndicator stopAnimating];
                self.neuralNetActivityIndicator.hidden = YES;
            });
            
            [self speakResults];
        }
    } else {
        NSLog(@"Unable to classify image %@", error.localizedDescription);
        return;
    }
}

- (void)speakResults {
    //speak results
    
    isRecognizing = NO;
    touchesActive = NO;
    
    if ([recognitionLanguage isEqualToString:@"English"]) {
        //Speak in English
        dispatch_async(dispatch_get_main_queue(), ^{
            self.recognizedObjectLabel.text = neuralNetworkResult;
            self.recognizedObjectLabel.hidden = NO;
        });
        
        NSTimer *timer;
        timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideLabel) userInfo:nil repeats:NO];
        
        NSString *stringToSpeak = [@"You are looking at a " stringByAppendingString:neuralNetworkResult];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:stringToSpeak];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"French"]) {
        //Speak in French
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Spanish"]) {
        //Speak in Spanish
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Russian"]) {
        //Speak in Russian
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"German"]) {
        //Speak in German
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Mandarin"]) {
        //Speak in Mandarin
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
    else if ([recognitionLanguage isEqualToString:@"Italian"]) {
        //Speak in Italian
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc]initWithString:@"You are looking at a "];
        [utterance setVoice:[AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"]];
        [utterance setRate:.5];
        [self.synthesizer speakUtterance:utterance];
    }
}

- (void)grabFrameFromVideo {
    //Grab still frame from video stream and store it as a UIImage
    
    // Not deprecated code that makes the app crash.
    
    // A loop with a purpose that is unknown.
    /* AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in photoOutput.connections)
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
    } */
    
    NSLog(@"about to request a capture from: %@", photoOutput);
    
    AVCapturePhotoSettings *settings;
    if ([photoOutput.availablePhotoCodecTypes containsObject:AVVideoCodecTypeJPEG]) {
        settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: AVVideoCodecTypeJPEG}];
    } else {
        settings = [[AVCapturePhotoSettings alloc] init];
    }
    settings.flashMode = AVCaptureFlashModeAuto;
    [photoOutput capturePhotoWithSettings:settings delegate:self];
    
    // Deprecated code
    /*
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
     }]; */
}

#pragma mark - Photo output delegate

- (void)captureOutput:(AVCapturePhotoOutput *)output didCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings {
    NSLog(@"Terminating speech recognition...");
    
    isRecording = NO;
    isRecognizing = YES;
    
    [self.audioEngine stop];
    [self.request endAudio];
    [inputNode removeTapOnBus:0];
    
    self.request = nil;
    self.recognitionTask = nil;
    
    if (!self.audioEngine.isRunning) {
        NSLog(@"The audio engine was stopped.");
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (!error) {
        NSData *imageData = photo.fileDataRepresentation;
        UIImage *image = [UIImage imageWithData:imageData];
        
        self.vImage.image = image;
        
        [self runNeuralNet];
        
        /* dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [self runNeuralNet];
        }); */
    }
    
    
    /* UIGraphicsBeginImageContextWithOptions(CGSizeMake(299, 299), YES, 2.0);
    [image drawInRect:CGRectMake(0, 0, 299, 299)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    self.vImage.image = newImage; */
    
    
}

- (void)beginNativeSpeechRecognition {
    NSLog(@"Setting up speech recognition...");
    
    if (self.recognitionTask != nil) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }
    
    if (inputNode.numberOfOutputs > 0) {
        [inputNode removeTapOnBus:0];
    }
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [audioSession setMode:AVAudioSessionModeSpokenAudio error:nil];
    [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *desc in currentRoute.outputs) {
        if (desc.portType == AVAudioSessionPortHeadphones) {
            NSLog(@"Headphones are plugged in. Nothing will be overriden.");
            [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
        } else {
            [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        }
    }
    
    self.request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    
    inputNode = self.audioEngine.inputNode;
    self.request.shouldReportPartialResults = YES;
    
    self.recognitionTask = [self.recognizer recognitionTaskWithRequest:self.request delegate:self];
    
    AVAudioFormat *audioFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:audioFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self.request appendAudioPCMBuffer:buffer];
    }];
    
    [self.audioEngine prepare];
    
    NSError *error;
    [self.audioEngine startAndReturnError:&error];
    if (self.audioEngine.isRunning) {
        NSLog(@"Audio engine has been started.");
        isRecording = YES;
    } else {
        NSLog(@"Audio engine failed to start: %@", error.localizedDescription);
    }
}

- (void)processSpeech {
    NSLog(@"Recognized text: %@", recognizedText);
    
    if ([recognizedText containsString:@"in French"]) {
        recognitionLanguage = @"French";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in Spanish"]) {
        recognitionLanguage = @"Spanish";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in Russian"]) {
        recognitionLanguage = @"Russian";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in English"]) {
        recognitionLanguage = @"English";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in German"]) {
        recognitionLanguage = @"German";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in Mandarin"]) {
        recognitionLanguage = @"Mandarin";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"in Italian"]) {
        recognitionLanguage = @"Italian";
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"am I looking at now"] || [recognizedText containsString:@"what is this now"] || [recognizedText containsString:@"what about now"] || [recognizedText containsString:@"And now"]) {
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else if ([recognizedText containsString:@"am I looking at"] || [recognizedText containsString:@"what is this"]) {
        
        group = dispatch_group_create();
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            //Grab still frame from video and run neural net once that completes
            [self grabFrameFromVideo];
        });
    }
    else {
        //restart speech recognition
        if (touchesActive == NO) {
            if ([SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
                [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                    if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
                        [self performSelector:@selector(beginNativeSpeechRecognition) withObject:nil afterDelay:0.01];
                    }
                }];
            } else {
                [self performSelector:@selector(beginNativeSpeechRecognition) withObject:nil afterDelay:0.01];
            }
        }
    }
}

#pragma mark - Speech recognition delegate

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult {
    NSLog(@"The speech recognition is finished.");
}

- (void)speechRecognitionDidDetectSpeech:(SFSpeechRecognitionTask *)task {
    NSLog(@"Speech was detected");
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription {
    recognizedText = transcription.formattedString;
    if (task.state == SFSpeechRecognitionTaskStateRunning) {
        [self.silenceTimer invalidate];
        self.silenceTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(processSpeech) userInfo:nil repeats:NO];
    } else if (task.state == SFSpeechRecognitionTaskStateStarting) {
        self.silenceTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer * _Nonnull timer) {
            
        }];
    }
    // self.silenceTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(processSpeech) userInfo:nil repeats:NO];
}

- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    if (!available) {
        NSLog(@"Speech recognition is no longer available. Any ongoing recognition should be cancelled.");
    }
}

@end
