//
//  ViewController.m
//  ANSMTPMessage
//
//  Created by HuaSheng on 2018/6/19.
//  Copyright © 2018年 AZP. All rights reserved.
//

#import "ViewController.h"
#import "ANSMTPMessage.h"
#import "ANSMTPMessageManager.h"
@interface ViewController ()<ANSMTPMessageDelegate>
@property(nonatomic, strong) ANSMTPMessage *message;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    

}



- (IBAction)sendMailFromQQ:(id)sender {
    [self mailFromQQ];
}


- (IBAction)sendMainFrom163:(id)sender {
    [self mailFrom163];
}


- (void)mailFromQQ{
    [ANSMTPMessageManager setupConfigWithServer:@"smtp.qq.com" withFrom:@"你的qq邮箱@qq.com" withPassword:@"授权码"];
    
    
    NSString * sb = [NSString stringWithFormat:@"%ld",random()%100000];
    NSString * body = [NSString stringWithFormat:@"%ld",random()%100000];
    NSArray * cc = @[@"xxx@163.com",@"xxx@csc-sz.com"];
   // NSString * path =[[NSBundle mainBundle] pathForResource:@"ex.txt" ofType:nil];
    [ANSMTPMessageManager sendMaileWithTo:@"收件箱" cc:cc subject:sb body:body path:nil delegate:self];
}

- (void)mailFrom163{
    
    [ANSMTPMessageManager setupConfigWithServer:@"smtp.163.com" withFrom:@"xxxxx@163.com" withPassword:@"xxxxx"];
    
    
    NSString * sb = [NSString stringWithFormat:@"%ld",random()%100000];
    NSString * body = [NSString stringWithFormat:@"%ld",random()%100000];
    NSArray * cc = @[@"xxxxxxx@csc-sz.com"];
    NSString * path =[[NSBundle mainBundle] pathForResource:@"ex.txt" ofType:nil];
    
    [ANSMTPMessageManager sendMaileWithTo:@"xxxxxx@qq.com" cc:cc subject:sb body:body path:path delegate:self];
}


- (void)messageSent:(ANSMTPMessage *)message{
    
    NSLog(@"邮件发送成功了");
}

- (void)messageFailed:(ANSMTPMessage *)message error:(NSError *)error{
    
    NSLog(@"邮件发送失败了 ：%@",error);
  
}




- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
