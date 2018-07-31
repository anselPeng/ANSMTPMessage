//
//  ANSMTPMessage.m
//  ANSMTPMessage
//
//  Created by HuaSheng on 2018/6/19.
//  Copyright © 2018年 AZP. All rights reserved.
//

#import "ANSMTPMessage.h"

#import "NSData+Base64Additions.h"
#import "HSK_CFUtilities.h"
 const  NSString *kANSMTPPartContentDispositionKey = @"kSKPSMTPPartContentDispositionKey";
 const  NSString *kANSMTPPartContentTypeKey = @"kSKPSMTPPartContentTypeKey";
 const  NSString *kANSMTPPartMessageKey = @"kSKPSMTPPartMessageKey";
 const  NSString *kANSMTPPartContentTransferEncodingKey = @"kSKPSMTPPartContentTransferEncodingKey";

#define SHORT_LIVENESS_TIMEOUT 20.0
#define LONG_LIVENESS_TIMEOUT 60.0

@interface ANSMTPMessage (){
    
    BOOL _serverAuthCRAMMD5;
    BOOL _serverAuthPLAIN;
    BOOL _serverAuthLOGIN;
    BOOL _serverAuthDIGESTMD5;
    BOOL _server8bitMessages;
    
}

@property(nonatomic, strong) NSTimer *connectTimer;
@property(nonatomic, strong) NSTimer *watchdogTimer;
@property(nonatomic, assign) NSTimeInterval connectTimeout;
@property(nonatomic, assign) ANSMTPState sendState;
@property(nonatomic, strong) NSMutableString *inputString;
@property(nonatomic, strong) NSOutputStream *outputStream;
@property(nonatomic, strong) NSInputStream *inputStream;
@property(nonatomic, assign) BOOL isSecure;


@end

@implementation ANSMTPMessage







#pragma mark -
#pragma mark Memory & Lifecycle

- (id)init
{
    static NSArray *defaultPorts = nil;
    
    if (!defaultPorts)
    {
        defaultPorts = [[NSArray alloc] initWithObjects:[NSNumber numberWithShort:25], [NSNumber numberWithShort:465], [NSNumber numberWithShort:587], nil];
    }
    
    if ((self = [super init]))
    {
        // Setup the default ports
        self.relayPorts = defaultPorts;
        
        // setup a default timeout (8 seconds)
       self.connectTimeout = 8.0;
        
        // by default, validate the SSL chain
       self.validateSSLChain = YES;
    }
    
    return self;
}

- (void)dealloc
{
    NSLog(@"dealloc %@", self);
}


#pragma mark -
#pragma mark Connection Timers

- (void)startShortWatchdog
{
    NSLog(@"*** starting short watchdog ***");
    self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:SHORT_LIVENESS_TIMEOUT target:self selector:@selector(connectionWatchdog:) userInfo:nil repeats:NO];
}

- (void)startLongWatchdog
{
    NSLog(@"*** starting long watchdog ***");
    self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_LIVENESS_TIMEOUT target:self selector:@selector(connectionWatchdog:) userInfo:nil repeats:NO];
}

- (void)stopWatchdog
{
    NSLog(@"*** stopping watchdog ***");
    [self.watchdogTimer invalidate];
    self.watchdogTimer = nil;
}


#pragma mark Watchdog Callback

- (void)connectionWatchdog:(NSTimer *)aTimer
{
    [self cleanUpStreams];
    
    // No hard error if we're wating on a reply
    if (self.sendState != kANSMTPWaitingQuitReply)
    {
        NSError *error = [NSError errorWithDomain:@"ANSMTPMessageError"
                                             code:kANSMPTErrorConnectionTimeout
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Timeout sending message.", @"server timeout fail error description"),NSLocalizedDescriptionKey,
                                                   NSLocalizedString(@"Try sending your message again later.", @"server generic error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
        [self.delegate messageFailed:self error:error];
    }
    else
    {
        [self.delegate messageSent:self];
    }
}

#pragma mark -
#pragma mark Connection Handling

- (BOOL)preflightCheckWithError:(NSError **)error {
    
    CFHostRef host = CFHostCreateWithName(NULL, (__bridge CFStringRef)self.relayHost);
    CFStreamError streamError;
    
    if (!CFHostStartInfoResolution(host, kCFHostAddresses, &streamError)) {
        NSString *errorDomainName;
        switch (streamError.domain) {
            case kCFStreamErrorDomainCustom:
                errorDomainName = @"kCFStreamErrorDomainCustom";
                break;
            case kCFStreamErrorDomainPOSIX:
                errorDomainName = @"kCFStreamErrorDomainPOSIX";
                break;
            case kCFStreamErrorDomainMacOSStatus:
                errorDomainName = @"kCFStreamErrorDomainMacOSStatus";
                break;
            default:
                errorDomainName = [NSString stringWithFormat:@"Generic CFStream Error Domain %ld", streamError.domain];
                break;
        }
        if (error)
            *error = [NSError errorWithDomain:errorDomainName
                                         code:streamError.error
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Error resolving address.", NSLocalizedDescriptionKey,
                                               @"Check your SMTP Host name", NSLocalizedRecoverySuggestionErrorKey, nil]];
        CFRelease(host);
        return NO;
    }
    Boolean hasBeenResolved;
    CFHostGetAddressing(host, &hasBeenResolved);
    if (!hasBeenResolved) {
        if(error)
            *error = [NSError errorWithDomain:@"ANSMTPMessageError" code:kANSMTPErrorNonExistentDomain userInfo:
                      [NSDictionary dictionaryWithObjectsAndKeys:@"Error resolving host.", NSLocalizedDescriptionKey,
                       @"Check your SMTP Host name", NSLocalizedRecoverySuggestionErrorKey, nil]];
        CFRelease(host);
        return NO;
    }
    
    CFRelease(host);
    return YES;
}


- (BOOL)send
{
    NSAssert(self.sendState == kANSMTPIdle, @"Message has already been sent!");
    
    if (self.requiresAuth)
    {
        NSAssert(self.login, @"auth requires login");
        NSAssert(self.pass, @"auth requires pass");
    }
    
    NSAssert(self.relayHost, @"send requires relayHost");
    NSAssert(self.subject, @"send requires subject");
    NSAssert(self.fromEmail, @"send requires fromEmail");
    NSAssert(self.toEmail, @"send requires toEmail");
    NSAssert(self.parts, @"send requires parts");
    
    NSError *error = nil;
    if (![self preflightCheckWithError:&error]) {
        [self.delegate messageFailed:self error:error];
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    if (![self.relayPorts count])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.delegate messageFailed:self
                              error:[NSError errorWithDomain:@"ANSMTPMessageError"
                                                        code:kANSMTPErrorConnectionFailed
                                                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to connect to the server.", @"server connection fail error description"),NSLocalizedDescriptionKey,
                                                              NSLocalizedString(@"Try sending your message again later.", @"server generic error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]]];
            
        });
        
        return NO;
    }
    
    // Grab the next relay port
    short relayPort = [[self.relayPorts objectAtIndex:0] shortValue];
    
    // Pop this off the head of the queue.
    self.relayPorts = ([self.relayPorts count] > 1) ? [self.relayPorts subarrayWithRange:NSMakeRange(1, [self.relayPorts count] - 1)] : [NSArray array];
    
    NSLog(@"C: Attempting to connect to server at: %@:%d", self.relayHost, relayPort);
    
    
    self.connectTimer = [NSTimer timerWithTimeInterval:self.connectTimeout target:self selector:@selector(connectionConnectedCheck:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.connectTimer forMode:NSDefaultRunLoopMode];
    
    
    CFReadStreamRef  readStream;
    CFWriteStreamRef writeStream = (__bridge CFWriteStreamRef)(self.outputStream);
    
    
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.relayHost, relayPort, &readStream, &writeStream);
    

   // [NSStream getStreamsToHostNamed:relayHost port:relayPort inputStream:&inputStream outputStream:&outputStream];
    
    self.inputStream = (__bridge NSInputStream *)(readStream);
    self.outputStream = (__bridge NSOutputStream *)(writeStream);
    
    if ((self.inputStream != nil) && (self.outputStream != nil))
    {
        self.sendState = kANSMTPConnecting;
        self.isSecure = NO;
        
        [self.inputStream setDelegate:self];
        [self.outputStream setDelegate:self];
        
        [self.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        [self.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        [self.inputStream open];
        [self.outputStream open];
        
        self.inputString = [NSMutableString string];
        
        
        
        return YES;
    }
    else
    {
        [self.connectTimer invalidate];
        self.connectTimer = nil;
        
        [self.delegate messageFailed:self
                          error:[NSError errorWithDomain:@"ANSMTPMessageError"
                                                    code:kANSMTPErrorConnectionFailed
                                                userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to connect to the server.", @"server connection fail error description"),NSLocalizedDescriptionKey,
                                                          NSLocalizedString(@"Try sending your message again later.", @"server generic error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]]];
        
        return NO;
    }
}

#pragma mark -
#pragma mark <NSStreamDelegate>

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch(eventCode)
    {
        case NSStreamEventHasBytesAvailable:
        {
            uint8_t buf[1024];
            memset(buf, 0, sizeof(uint8_t) * 1024);
            NSInteger len = 0;
            len = [(NSInputStream *)stream read:buf maxLength:1024];
            if(len)
            {
                NSString *tmpStr = [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding];
                if (tmpStr) {
                    [self.inputString appendString:tmpStr];
                    
                    [self parseBuffer];
                }
                
            }
            break;
        }
        case NSStreamEventEndEncountered:
        {
            [self stopWatchdog];
            [stream close];
            [stream removeFromRunLoop:[NSRunLoop currentRunLoop]
                              forMode:NSDefaultRunLoopMode];
            stream = nil; // stream is ivar, so reinit it
            
            if (self.sendState != kANSMTPMessageSent)
            {
                [self.delegate messageFailed:self
                                  error:[NSError errorWithDomain:@"ANSMTPMessageError"
                                                            code:kANSMTPErrorConnectionInterrupted
                                                        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"The connection to the server was interrupted.", @"server connection interrupted error description"),NSLocalizedDescriptionKey,
                                                                  NSLocalizedString(@"Try sending your message again later.", @"server generic error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]]];
                
            }
            
            break;
        }
        default:
            break;
    }
}


- (NSString *)formatAnAddress:(NSString *)address {
    NSString        *formattedAddress;
    NSCharacterSet    *whitespaceCharSet = [NSCharacterSet whitespaceCharacterSet];
    
    if (([address rangeOfString:@"<"].location == NSNotFound) && ([address rangeOfString:@">"].location == NSNotFound)) {
        formattedAddress = [NSString stringWithFormat:@"RCPT TO:<%@>\r\n", [address stringByTrimmingCharactersInSet:whitespaceCharSet]];
    }
    else {
        formattedAddress = [NSString stringWithFormat:@"RCPT TO:%@\r\n", [address stringByTrimmingCharactersInSet:whitespaceCharSet]];
    }
    
    return(formattedAddress);
}

- (NSString *)formatAddresses:(NSString *)addresses {
    NSCharacterSet    *splitSet = [NSCharacterSet characterSetWithCharactersInString:@";,"];
    NSMutableString    *multipleRcptTo = [NSMutableString string];
    
    if ((addresses != nil) && (![addresses isEqualToString:@""])) {
        if( [addresses rangeOfString:@";"].location != NSNotFound || [addresses rangeOfString:@","].location != NSNotFound ) {
            NSArray *addressParts = [addresses componentsSeparatedByCharactersInSet:splitSet];
            
            for( NSString *address in addressParts ) {
                [multipleRcptTo appendString:[self formatAnAddress:address]];
            }
        }
        else {
            [multipleRcptTo appendString:[self formatAnAddress:addresses]];
        }
    }
    
    return(multipleRcptTo);
}


- (void)parseBuffer
{
    // Pull out the next line
    NSScanner *scanner = [NSScanner scannerWithString:self.inputString];
    NSString *tmpLine = nil;
    
    NSError *error = nil;
    BOOL encounteredError = NO;
    BOOL messageSent = NO;
    NSLog(@"*******%@",self.inputString);
    while (![scanner isAtEnd])
    {
        BOOL foundLine = [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet]
                                                 intoString:&tmpLine];
        if (foundLine)
        {
            [self stopWatchdog];
            
            NSLog(@"SSSSS: %@", tmpLine);
            switch (self.sendState)
            {
                case kANSMTPConnecting:
                {
                    if ([tmpLine hasPrefix:@"220 "])
                    {
                        
                        self.sendState = kANSMTPWaitingEHLOReply;
                        
                        NSString *ehlo = [NSString stringWithFormat:@"EHLO %@\r\n", @"localhost"];
                        NSLog(@"C: %@", ehlo);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[ehlo UTF8String], [ehlo lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    break;
                }
                case kANSMTPWaitingEHLOReply:
                {
                    // Test auth login options
                    if ([tmpLine hasPrefix:@"250-AUTH"])
                    {
                        NSRange testRange;
                        testRange = [tmpLine rangeOfString:@"CRAM-MD5"];
                        if (testRange.location != NSNotFound)
                        {
                            _serverAuthCRAMMD5 = YES;
                        }
                        
                        testRange = [tmpLine rangeOfString:@"PLAIN"];
                        if (testRange.location != NSNotFound)
                        {
                            _serverAuthPLAIN = YES;
                        }
                        
                        testRange = [tmpLine rangeOfString:@"LOGIN"];
                        if (testRange.location != NSNotFound)
                        {
                            _serverAuthLOGIN = YES;
                        }
                        
                        testRange = [tmpLine rangeOfString:@"DIGEST-MD5"];
                        if (testRange.location != NSNotFound)
                        {
                            _serverAuthDIGESTMD5 = YES;
                        }
                    }
                    else if ([tmpLine hasPrefix:@"250-8BITMIME"])
                    {
                        _server8bitMessages = YES;
                    }
                    else if ([tmpLine hasPrefix:@"250-STARTTLS"] && !self.isSecure && self.wantsSecure)
                    {
                        // if we're not already using TLS, start it up
                        _sendState = kANSMTPWaitingTLSReply;
                        
                        NSString *startTLS = @"STARTTLS\r\n";
                        NSLog(@"C: %@", startTLS);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[startTLS UTF8String], [startTLS lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    else if ([tmpLine hasPrefix:@"250 "])
                    {
                        if (self.requiresAuth)
                        {
                            // Start up auth
                            if (_serverAuthPLAIN)
                            {
                                self.sendState = kANSMTPWaitingAuthSuccess;
                                NSString *loginString = [NSString stringWithFormat:@"\000%@\000%@", self.login, self.pass];
                                NSString *authString = [NSString stringWithFormat:@"AUTH PLAIN %@\r\n", [[loginString dataUsingEncoding:NSUTF8StringEncoding] encodeBase64ForData]];
                                NSLog(@"C: %@", authString);
                                if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[authString UTF8String], [authString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                                {
                                    error =  [self.outputStream streamError];
                                    encounteredError = YES;
                                }
                                else
                                {
                                    [self startShortWatchdog];
                                }
                            }
                            else if (_serverAuthLOGIN)
                            {
                                self.sendState = kANSMTPWaitingLOGINUsernameReply;
                                NSString *authString = @"AUTH LOGIN\r\n";
                                NSLog(@"C: %@", authString);
                                if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[authString UTF8String], [authString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                                {
                                    error =  [self.outputStream streamError];
                                    encounteredError = YES;
                                }
                                else
                                {
                                    [self startShortWatchdog];
                                }
                            }
                            else
                            {
                                error = [NSError errorWithDomain:@"ANSMTPMessageError"
                                                            code:kANSMTPErrorUnsupportedLogin
                                                        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unsupported login mechanism.", @"server unsupported login fail error description"),NSLocalizedDescriptionKey,
                                                                  NSLocalizedString(@"Your server's security setup is not supported, please contact your system administrator or use a supported email account like MobileMe.", @"server security fail error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
                                
                                encounteredError = YES;
                            }
                            
                        }
                        else
                        {
                            // Start up send from
                            self.sendState = kANSMTPWaitingFromReply;
                            
                            NSString *mailFrom = [NSString stringWithFormat:@"MAIL FROM:<%@>\r\n", self.fromEmail];
                            NSLog(@"C: %@", mailFrom);
                            if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[mailFrom UTF8String], [mailFrom lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                            {
                                error =  [self.outputStream streamError];
                                encounteredError = YES;
                            }
                            else
                            {
                                [self startShortWatchdog];
                            }
                        }
                    }
                    break;
                }
                    
                case kANSMTPWaitingTLSReply:
                {
                    if ([tmpLine hasPrefix:@"220 "])
                    {
                        
                        // Attempt to use TLSv1
                        CFMutableDictionaryRef sslOptions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                        
                        CFDictionarySetValue(sslOptions, kCFStreamSSLLevel, kCFStreamSocketSecurityLevelTLSv1);
                        
                        if (!self.validateSSLChain)
                        {
                            // Don't validate SSL certs. This is terrible, please complain loudly to your BOFH.
                            NSLog(@"WARNING: Will not validate SSL chain!!!");
                            
                            CFDictionarySetValue(sslOptions, kCFStreamSSLValidatesCertificateChain, kCFBooleanFalse);
                            //                            CFDictionarySetValue(sslOptions, kCFStreamSSLAllowsExpiredCertificates, kCFBooleanTrue);
                            //                            CFDictionarySetValue(sslOptions, kCFStreamSSLAllowsExpiredRoots, kCFBooleanTrue);
                            //                            CFDictionarySetValue(sslOptions, kCFStreamSSLAllowsAnyRoot, kCFBooleanTrue);
                        }
                        
                        NSLog(@"Beginning TLSv1...");
                        
                        CFReadStreamSetProperty((CFReadStreamRef)self.inputStream, kCFStreamPropertySSLSettings, sslOptions);
                        CFWriteStreamSetProperty((CFWriteStreamRef)self.outputStream, kCFStreamPropertySSLSettings, sslOptions);
                        
                        CFRelease(sslOptions);
                        
                        // restart the connection
                        self.sendState = kANSMTPWaitingEHLOReply;
                        self.isSecure = YES;
                        
                        NSString *ehlo = [NSString stringWithFormat:@"EHLO %@\r\n", @"localhost"];
                        NSLog(@"C: %@", ehlo);
                        
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[ehlo UTF8String], [ehlo lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                        
                        /*
                         else
                         {
                         error = [NSError errorWithDomain:@"ANSMTPMessageError"
                         code:kANSMTPErrorTLSFail
                         userInfo:[NSDictionary dictionaryWithObject:@"Unable to start TLS"
                         forKey:NSLocalizedDescriptionKey]];
                         encounteredError = YES;
                         }
                         */
                    }
                }
                    
                case kANSMTPWaitingLOGINUsernameReply:
                {
                    if ([tmpLine hasPrefix:@"334 VXNlcm5hbWU6"])
                    {
                        self.sendState = kANSMTPWaitingLOGINPasswordReply;
                        
                        NSString *authString = [NSString stringWithFormat:@"%@\r\n", [[self.login dataUsingEncoding:NSUTF8StringEncoding] encodeBase64ForData]];
                        NSLog(@"C: %@", authString);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[authString UTF8String], [authString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    break;
                }
                    
                case kANSMTPWaitingLOGINPasswordReply:
                {
                    if ([tmpLine hasPrefix:@"334 UGFzc3dvcmQ6"])
                    {
                        self.sendState = kANSMTPWaitingAuthSuccess;
                        
                        NSString *authString = [NSString stringWithFormat:@"%@\r\n", [[self.pass dataUsingEncoding:NSUTF8StringEncoding] encodeBase64ForData]];
                        NSLog(@"C: %@", authString);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[authString UTF8String], [authString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    break;
                }
                    
                case kANSMTPWaitingAuthSuccess:
                {
                    if ([tmpLine hasPrefix:@"235 "])
                    {
                        self.sendState = kANSMTPWaitingFromReply;
                        
                        NSString *mailFrom = _server8bitMessages ? [NSString stringWithFormat:@"MAIL FROM:<%@> BODY=8BITMIME\r\n", self.fromEmail] : [NSString stringWithFormat:@"MAIL FROM:<%@>\r\n", self.fromEmail];
                        NSLog(@"C: %@", mailFrom);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[mailFrom cStringUsingEncoding:NSASCIIStringEncoding], [mailFrom lengthOfBytesUsingEncoding:NSASCIIStringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    else if ([tmpLine hasPrefix:@"535 "])
                    {
                        error =[NSError errorWithDomain:@"ANSMTPMessageError"
                                                   code:kANSMTPErrorInvalidUserPass
                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Invalid username or password.", @"server login fail error description"),NSLocalizedDescriptionKey,
                                                         NSLocalizedString(@"Go to Email Preferences in the application and re-enter your username and password.", @"server login error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
                        encounteredError = YES;
                    }
                    break;
                }
                    
                case kANSMTPWaitingFromReply:
                {
                    // toc 2009-02-18 begin changes per mdesaro issue 18 - http://code.google.com/p/ANsmtpmessage/issues/detail?id=18
                    // toc 2009-02-18 begin changes to support cc & bcc
                    
                    if ([tmpLine hasPrefix:@"250 "]) {
                        self.sendState = kANSMTPWaitingToReply;
                        
                        NSMutableString    *multipleRcptTo = [NSMutableString string];
                        [multipleRcptTo appendString:[self formatAddresses:self.toEmail]];
                        [multipleRcptTo appendString:[self formatAddresses:self.ccEmail]];
                        [multipleRcptTo appendString:[self formatAddresses:self.bccEmail]];
                        
                        NSLog(@"C: %@", multipleRcptTo);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[multipleRcptTo UTF8String], [multipleRcptTo lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    break;
                }
                case kANSMTPWaitingToReply:
                {
                    if ([tmpLine hasPrefix:@"250 "])
                    {
                        self.sendState = kANSMTPWaitingForEnterMail;
                        
                        NSString *dataString = @"DATA\r\n";
                        NSLog(@"C: %@", dataString);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[dataString UTF8String], [dataString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    else if ([tmpLine hasPrefix:@"530 "])
                    {
                        error =[NSError errorWithDomain:@"ANSMTPMessageError"
                                                   code:kANSMTPErrorNoRelay
                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Relay rejected.", @"server relay fail error description"),NSLocalizedDescriptionKey,
                                                         NSLocalizedString(@"Your server probably requires a username and password.", @"server relay fail error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
                        encounteredError = YES;
                    }
                    else if ([tmpLine hasPrefix:@"550 "])
                    {
                        error =[NSError errorWithDomain:@"ANSMTPMessageError"
                                                   code:kANSMTPErrorInvalidMessage
                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"To address rejected.", @"server to address fail error description"),NSLocalizedDescriptionKey,
                                                         NSLocalizedString(@"Please re-enter the To: address.", @"server to address fail error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
                        encounteredError = YES;
                    }
                    break;
                }
                case kANSMTPWaitingForEnterMail:
                {
                    if ([tmpLine hasPrefix:@"354 "])
                    {
                        self.sendState = kANSMTPWaitingSendSuccess;
                        
                        if (![self sendParts])
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                    }
                    break;
                }
                case kANSMTPWaitingSendSuccess:
                {
                    if ([tmpLine hasPrefix:@"250 "])
                    {
                       self.sendState = kANSMTPWaitingQuitReply;
                        
                        NSString *quitString = @"QUIT\r\n";
                        NSLog(@"C: %@", quitString);
                        if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[quitString UTF8String], [quitString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
                        {
                            error =  [self.outputStream streamError];
                            encounteredError = YES;
                        }
                        else
                        {
                            [self startShortWatchdog];
                        }
                    }
                    else if ([tmpLine hasPrefix:@"550 "])
                    {
                        error =[NSError errorWithDomain:@"ANSMTPMessageError"
                                                   code:kANSMTPErrorInvalidMessage
                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Failed to logout.", @"server logout fail error description"),NSLocalizedDescriptionKey,
                                                         NSLocalizedString(@"Try sending your message again later.", @"server generic error recovery"),NSLocalizedRecoverySuggestionErrorKey,nil]];
                        encounteredError = YES;
                    }else if ([tmpLine hasPrefix:@"554 "])
                    {
                        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:554 userInfo:@{@"msg":@"邮件被服务端拒了"}];
                        encounteredError = YES;
                        break;
                    }
                    
                }
                case kANSMTPWaitingQuitReply:
                {
                    if ([tmpLine hasPrefix:@"221 "])
                    {
                        self.sendState = kANSMTPMessageSent;
                        
                        messageSent = YES;
                    }
                }
            }
            
        }
        else
        {
            break;
        }
    }
    
    self.inputString = [[self.inputString substringFromIndex:[scanner scanLocation]] mutableCopy];
    if (messageSent)
    {
        [self cleanUpStreams];
        
        [self.delegate messageSent:self];
    }
    else if (encounteredError)
    {
        [self cleanUpStreams];
        
        [self.delegate messageFailed:self error:error];
    }
}

- (BOOL)sendParts
{
    NSMutableString *message = [[NSMutableString alloc] init];
    static NSString *separatorString = @"--ANSMTPMessage--Separator--Delimiter\r\n";
    
    CFUUIDRef    uuidRef   = CFUUIDCreate(kCFAllocatorDefault);
    NSString    *uuid     = (NSString *)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, uuidRef));
    CFRelease(uuidRef);
    
    NSDate *now = [[NSDate alloc] init];
    NSDateFormatter    *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss Z"];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    [message appendFormat:@"Date: %@\r\n", [dateFormatter stringFromDate:now]];
    [message appendFormat:@"Message-id: <%@@%@>\r\n", [(NSString *)uuid stringByReplacingOccurrencesOfString:@"-" withString:@""], self.relayHost];
    

    
    [message appendFormat:@"From:%@\r\n", self.fromEmail];
    
    
    if ((self.toEmail != nil) && (![self.toEmail isEqualToString:@""]))
    {
        [message appendFormat:@"To:%@\r\n", self.toEmail];
    }
    
    if ((self.ccEmail != nil) && (![self.ccEmail isEqualToString:@""]))
    {
        [message appendFormat:@"Cc:%@\r\n", self.ccEmail];
    }
    
    [message appendString:@"Content-Type: multipart/mixed; boundary=ANSMTPMessage--Separator--Delimiter\r\n"];
    [message appendString:@"Mime-Version: 1.0 (ANSMTPMessage 1.0)\r\n"];
    [message appendFormat:@"Subject:%@\r\n\r\n",self.subject];
    [message appendString:separatorString];
    
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];

    
    NSLog(@"C: %s", [messageData bytes]);
    if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[messageData bytes], [messageData length]) < 0)
    {
        return NO;
    }
    
    message = [[NSMutableString alloc] init];
    
    for (NSDictionary *part in self.parts)
    {
        if ([part objectForKey:kANSMTPPartContentDispositionKey])
        {
            [message appendFormat:@"Content-Disposition: %@\r\n", [part objectForKey:kANSMTPPartContentDispositionKey]];
        }
        [message appendFormat:@"Content-Type: %@\r\n", [part objectForKey:kANSMTPPartContentTypeKey]];
        [message appendFormat:@"Content-Transfer-Encoding: %@\r\n\r\n", [part objectForKey:kANSMTPPartContentTransferEncodingKey]];
        [message appendString:[part objectForKey:kANSMTPPartMessageKey]];
        [message appendString:@"\r\n"];
        [message appendString:separatorString];
    }
    
    [message appendString:@"\r\n.\r\n"];
    
    NSLog(@"C: %@", message);
    if (CFWriteStreamWriteFully((__bridge CFWriteStreamRef)self.outputStream, (const uint8_t *)[message UTF8String], [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) < 0)
    {
  
        return NO;
    }
    [self startLongWatchdog];
    return YES;
}

- (void)connectionConnectedCheck:(NSTimer *)aTimer
{
    if (self.sendState == kANSMTPConnecting)
    {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
        self.outputStream = nil;
        
        // Try the next port - if we don't have another one to try, this will fail
        self.sendState = kANSMTPIdle;
        [self send];
    }
    
    self.connectTimer = nil;
}


- (void)cleanUpStreams
{
    [self.inputStream close];
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                           forMode:NSDefaultRunLoopMode];
    self.inputStream = nil;
    
    [self.outputStream close];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSDefaultRunLoopMode];
    self.outputStream = nil;
}


@end
