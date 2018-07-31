//
//  ANSMTPMessageManager.m
//  ANSMTPMessage
//
//  Created by HuaSheng on 2018/6/20.
//  Copyright © 2018年 AZP. All rights reserved.
//

#import "ANSMTPMessageManager.h"

#import "NSData+Base64Additions.h"
@interface ANSMTPMessageManager(){
    
    NSString * _server;
    NSString * _from;
    NSString * _pass;
}

@property(nonatomic, strong) NSMutableArray * messages;


@end;


@implementation ANSMTPMessageManager

+(instancetype)shareManager{
    
    static ANSMTPMessageManager * instance = nil;
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init] ;;
    });
    return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone{
    return [self shareManager];
}

- (id)copyWithZone:(NSZone *)zone{
    return [ANSMTPMessageManager shareManager];
}

+ (void)setupConfigWithServer:(NSString *)server
                     withFrom:(NSString *)from
                 withPassword:(NSString *)password{
    ANSMTPMessageManager *m = [ANSMTPMessageManager shareManager];
    [m configWithServer:server withFrom:from withPassword:password];
}

- (void)configWithServer:(NSString *)server
                withFrom:(NSString *)from
            withPassword:(NSString *)password{
    _sever = server;
    _from = from;
    _pass = password;
}

+(void)sendMaileWithTo:(NSString *)to
                    cc:(NSArray *)cc
               subject:(NSString *)subject
                  body:(NSString *)body
                  path:(NSString *)path
              delegate:(id <ANSMTPMessageDelegate>)delegate{
    
    
    
    ANSMTPMessageManager *manager = [ANSMTPMessageManager shareManager];
    ANSMTPMessage * message = [manager creatMessageWithTo:to cc:cc subject:subject body:body path:path];
    message.delegate = delegate;
    if (message) {
        [manager.messages addObject:message];
        [message send];
    } else {
        NSLog(@"邮件创建失败");
        //[self.];
    }
    
}


- (ANSMTPMessage *)creatMessageWithTo:(NSString *)to
                                   cc:(NSArray *)cc
                              subject:(NSString *)subject
                                 body:(NSString *)body
                                 path:(NSString *)path{
    
    ANSMTPMessage *message= [ANSMTPMessage new];
    message.fromEmail = self.from;
    message.login = self.from;
    message.pass = self.pass;
    message.relayHost = self.sever;
    message.toEmail = to;
    message.ccEmail = [cc componentsJoinedByString:@","];
    message.subject = subject;
    message.requiresAuth = YES;
    message.wantsSecure = YES;
    NSDictionary *plainPart = [NSDictionary dictionaryWithObjectsAndKeys:@"text/plain",kANSMTPPartContentTypeKey,body,kANSMTPPartMessageKey,@"8bit",kANSMTPPartContentTransferEncodingKey,nil];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (path.length&&[fileManager fileExistsAtPath:path]) {
        
        NSString *fileName = [path lastPathComponent];
        
        NSData *vcfData = [NSData dataWithContentsOfFile:path];
        
        NSString *contentType = [NSString stringWithFormat:@"text/directory;\r\n\tx-unix-mode=0644;\r\n\tname=\"%@\"", fileName];
        NSString *attachment = [NSString stringWithFormat:@"attachment;\r\n\tfilename=\"%@\"", fileName];
        
        NSDictionary *vcfPart = [NSDictionary dictionaryWithObjectsAndKeys:contentType,kANSMTPPartContentTypeKey,
                                 attachment,kANSMTPPartContentDispositionKey,[vcfData encodeBase64ForData],kANSMTPPartMessageKey,@"base64",kANSMTPPartContentTransferEncodingKey,nil];
        
        message.parts = [NSArray arrayWithObjects:plainPart,vcfPart,nil];
    } else {
     message.parts = @[plainPart];
    }
    return message;
    
}




- (NSMutableArray *)messages{
    if (!_messages) {
        _messages = [NSMutableArray new];
    }
    return _messages;
}

@end
