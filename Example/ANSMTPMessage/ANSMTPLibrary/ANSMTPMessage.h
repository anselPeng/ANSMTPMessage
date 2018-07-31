//
//  ANSMTPMessage.h
//  ANSMTPMessage
//
//  Created by HuaSheng on 2018/6/19.
//  Copyright © 2018年 AZP. All rights reserved.
//

#import <Foundation/Foundation.h>


enum
{
    kANSMTPIdle = 0,
    kANSMTPConnecting,
    kANSMTPWaitingEHLOReply,
    kANSMTPWaitingTLSReply,
    kANSMTPWaitingLOGINUsernameReply,
    kANSMTPWaitingLOGINPasswordReply,
    kANSMTPWaitingAuthSuccess,
    kANSMTPWaitingFromReply,
    kANSMTPWaitingToReply,
    kANSMTPWaitingForEnterMail,
    kANSMTPWaitingSendSuccess,
    kANSMTPWaitingQuitReply,
    kANSMTPMessageSent
};
typedef NSUInteger ANSMTPState;


// Message part keys
extern const NSString *kANSMTPPartContentDispositionKey;
extern const NSString *kANSMTPPartContentTypeKey;
extern const NSString *kANSMTPPartMessageKey;
extern const NSString *kANSMTPPartContentTransferEncodingKey;

// Error message codes
#define kANSMPTErrorConnectionTimeout -5
#define kANSMTPErrorConnectionFailed -3
#define kANSMTPErrorConnectionInterrupted -4
#define kANSMTPErrorUnsupportedLogin -2
#define kANSMTPErrorTLSFail -1
#define kANSMTPErrorNonExistentDomain 1
#define kANSMTPErrorInvalidUserPass 535
#define kANSMTPErrorInvalidMessage 550
#define kANSMTPErrorNoRelay 530

@class ANSMTPMessage;

@protocol ANSMTPMessageDelegate
@required

-(void)messageSent:(ANSMTPMessage *)message;
-(void)messageFailed:(ANSMTPMessage *)message error:(NSError *)error;

@end



@interface ANSMTPMessage : NSObject<NSStreamDelegate>


@property(nonatomic, copy) NSString *login;
@property(nonatomic, copy) NSString *pass;
@property(nonatomic, copy) NSString *relayHost;
@property(nonatomic, weak) id <ANSMTPMessageDelegate> delegate;
@property(nonatomic, copy) NSArray *relayPorts;
@property(nonatomic, assign) BOOL requiresAuth;
@property(nonatomic, assign) BOOL wantsSecure;
@property(nonatomic, assign) BOOL validateSSLChain;
@property(nonatomic, copy) NSString *subject;
@property(nonatomic, copy) NSString *fromEmail;
@property(nonatomic, copy) NSString *toEmail;
@property(nonatomic, copy) NSString *ccEmail;
@property(nonatomic, copy) NSString *bccEmail;
@property(nonatomic, strong) NSArray *parts;

- (BOOL)send;
@end
