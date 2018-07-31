//
//  ANSMTPMessageManager.h
//  ANSMTPMessage
//
//  Created by HuaSheng on 2018/6/20.
//  Copyright © 2018年 AZP. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ANSMTPMessage.h"
@interface ANSMTPMessageManager : NSObject<NSCopying>

@property(nonatomic, copy,readonly) NSString *sever;
@property(nonatomic, copy,readonly) NSString *from;
@property(nonatomic, copy,readonly) NSString *pass;


+(instancetype)shareManager;

/**
 配置发件箱信息

 @param server 邮箱服务器，eg:@"smtp.qq.com" \ @"smtp.163.com"
 @param from 发件者邮箱
 @param password 发件邮箱SMTP授权码 获取授权码方式如下
 获取qq邮箱的授权码：https://jingyan.baidu.com/article/3052f5a1ee816d97f31f86b8.html
 获取163邮箱的授权码：https://jingyan.baidu.com/article/495ba841ecc72c38b30ede38.html
 
 */
+ (void)setupConfigWithServer:(NSString *)server
                     withFrom:(NSString *)from
                 withPassword:(NSString *)password;


/**
 邮件发送邮件

 @param to 收件邮箱
 @param cc cc邮箱
 @param subject 主题
 @param body 邮件内容
 @param path 附件地址（没有可传空）
 */
+(void)sendMaileWithTo:(NSString *)to
                    cc:(NSArray *)cc
               subject:(NSString *)subject
                  body:(NSString *)body
                  path:(NSString *)path
              delegate:(id<ANSMTPMessageDelegate>)delegate;


@end
