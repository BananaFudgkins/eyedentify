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
    
    AVCaptureSession *captureSession = [AVCaptureSession new];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    AVCaptureDeviceInput *cameraInput = [[AVCaptureDeviceInput alloc]initWithDevice:device error:&error];
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    
    stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
    [stillImageOutput setOutputSettings:outputSettings];
    
    [captureSession addInput:cameraInput];
    [captureSession addOutput:stillImageOutput];
    [captureSession startRunning];
    
    UIView *cameraView = [[UIView alloc]initWithFrame:self.view.frame];
    previewLayer.frame = cameraView.bounds;
    [cameraView.layer addSublayer:previewLayer];
    
    [self.view addSubview:cameraView];
    
    self.vImage = [[UIImageView alloc]init];
    
    OverlayViewController *overlayViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"OverlayViewController"];
    [self.view addSubview:overlayViewController.view];

    group = dispatch_group_create();
    [self grabFrameFromVideo];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        
    });
    
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
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    
}

- (void)recognizer:(SKRecognizer *)recognizer didFinishWithError:(NSError *)error suggestion:(NSString *)suggestion {

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

- (IBAction)fullScreenPressed:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"animateUp" object:sender];
}

@end
