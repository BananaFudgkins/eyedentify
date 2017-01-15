//
//  OverlayViewController.m
//  eyedentify
//
//  Created by Michael Royzen on 1/14/17.
//  Copyright © 2017 The Three Bruhsketeers. All rights reserved.
//

#import "OverlayViewController.h"

@interface OverlayViewController ()

@end

@implementation OverlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.iconBackground.layer.cornerRadius = self.iconBackground.frame.size.width / 2;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animateEverything:)
                                                 name:@"animateUp"
                                               object:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)animateEverything:(NSNotification *)note {
    UIButton *origin = note.object;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
