//
//  ViewController.m
//  eyedentify
//
//  Created by Michael Royzen on 1/14/17.
//  Copyright © 2017 The Three Bruhsketeers. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    AVCaptureSession *captureSession = [AVCaptureSession new];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    AVCaptureDeviceInput *cameraInput = [[AVCaptureDeviceInput alloc]initWithDevice:device error:&error];
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    [captureSession addInput:cameraInput];
    [captureSession startRunning];
    
    UIView *cameraView = [[UIView alloc]initWithFrame:self.view.frame];
    previewLayer.frame = cameraView.bounds;
    [cameraView.layer addSublayer:previewLayer];
    
    [self.view addSubview:cameraView];
    
    OverlayViewController *overlayViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"OverlayViewController"];
    [self.view addSubview:overlayViewController.view];

    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
