//
//  NotificationsDataSource.m
//
//  Copyright (C) 2015 IRCCloud, Ltd.
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <UserNotifications/UserNotifications.h>
#import "NotificationsDataSource.h"
#import "BuffersDataSource.h"
#import "EventsDataSource.h"
#import "NetworkConnection.h"

@implementation NotificationsDataSource
+(NotificationsDataSource *)sharedInstance {
    static NotificationsDataSource *sharedInstance;
    
    @synchronized(self) {
        if(!sharedInstance)
            sharedInstance = [[NotificationsDataSource alloc] init];
        
        return sharedInstance;
    }
    return nil;
}

-(id)init {
    self = [super init];
    if(self) {
        if(!_notifications)
            _notifications = [[NSMutableDictionary alloc] init];
        
        if([[[[UIDevice currentDevice].systemVersion componentsSeparatedByString:@"."] objectAtIndex:0] intValue] < 10 && [[[NSUserDefaults standardUserDefaults] objectForKey:@"cacheVersion"] isEqualToString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]]) {
            NSString *cacheFile = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"notifications"];
            
            @try {
                NSArray *ns = [[NSKeyedUnarchiver unarchiveObjectWithFile:cacheFile] mutableCopy];
                for(UILocalNotification *n in ns) {
                    NSNumber *bid = [[n.userInfo objectForKey:@"d"] objectAtIndex:1];
                    if(![_notifications objectForKey:bid])
                        [_notifications setObject:[[NSMutableArray alloc] init] forKey:bid];
                    [[_notifications objectForKey:bid] addObject:n];
                }
            } @catch(NSException *e) {
                [[NSFileManager defaultManager] removeItemAtPath:cacheFile error:nil];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cacheVersion"];
            }
            CLS_LOG(@"NotificationsDataSource initialized with %lu items from cache", (unsigned long)_notifications.count);
        }
    }
    return self;
}

-(void)serialize {
    if(@available(iOS 10, *)) {
        return;
    }
    NSString *cacheFile = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"notifications"];
    
    NSMutableArray *n;
    @synchronized(_notifications) {
        for(NSNumber *bid in _notifications.allKeys) {
            [n addObjectsFromArray:[_notifications objectForKey:bid]];
        }
    }
    
    @synchronized(self) {
        @try {
            [NSKeyedArchiver archiveRootObject:n toFile:cacheFile];
            [[NSURL fileURLWithPath:cacheFile] setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:NULL];
        }
        @catch (NSException *exception) {
            [[NSFileManager defaultManager] removeItemAtPath:cacheFile error:nil];
        }
    }
}

-(void)clear {
    @synchronized(_notifications) {
        CLS_LOG(@"Clearing badge count");
        [_notifications removeAllObjects];
#ifndef EXTENSION
        [UIApplication sharedApplication].applicationIconBadgeNumber = 1;
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
        [[UIApplication sharedApplication] cancelAllLocalNotifications];
        if(@available(iOS 10, *)) {
            [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
        }
#endif
    }
}

-(void)notify:(NSString *)alert category:(NSString *)category cid:(int)cid bid:(int)bid eid:(NSTimeInterval)eid {
#ifndef EXTENSION
    if(@available(iOS 10, *)) {
#if TARGET_IPHONE_SIMULATOR
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = @"IRCCloud";
        content.body = alert;
        Buffer *b = [[BuffersDataSource sharedInstance] getBuffer:bid];
        content.userInfo = @{@"d": @[@(cid), @(bid), @(eid)], @"aps":@{@"alert":@{@"loc-args":@[b.name, b.name, b.name, b.name]}}};
        content.categoryIdentifier = category;
        
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[@(eid) stringValue] content:content trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
#endif
    } else {
        UILocalNotification *n = [[UILocalNotification alloc] init];
        if([n respondsToSelector:@selector(setAlertTitle:)])
            n.alertTitle = @"IRCCloud";
        n.alertBody = alert;
        n.alertAction = @"Reply";
        n.userInfo = @{@"d": @[@(cid), @(bid), @(eid)]};
        @synchronized(_notifications) {
            if(![_notifications objectForKey:@(bid)])
                [_notifications setObject:[[NSMutableArray alloc] init] forKey:@(bid)];
            
            NSArray *ns = [NSArray arrayWithArray:[_notifications objectForKey:@(bid)]];
            BOOL found = NO;
            for(UILocalNotification *n in ns) {
                NSArray *d = [n.userInfo objectForKey:@"d"];
                if([[d objectAtIndex:2] doubleValue] == eid) {
                    found = YES;
                    break;
                }
            }
            if(!found) {
                [[_notifications objectForKey:@(bid)] addObject:n];
                //[[UIApplication sharedApplication] presentLocalNotificationNow:n];
            }
        }
    }
#endif
}

-(void)removeNotificationsForBID:(int)bid olderThan:(NSTimeInterval)eid {
#ifndef EXTENSION
    @synchronized(_notifications) {
        NSArray *ns = [NSArray arrayWithArray:[_notifications objectForKey:@(bid)]];
        if([[[[UIDevice currentDevice].systemVersion componentsSeparatedByString:@"."] objectAtIndex:0] intValue] < 10) {
            for(UILocalNotification *n in ns) {
                NSArray *d = [n.userInfo objectForKey:@"d"];
                if([[d objectAtIndex:1] intValue] == bid && [[d objectAtIndex:2] doubleValue] <= eid) {
                    //[[UIApplication sharedApplication] cancelLocalNotification:n];
                    [[_notifications objectForKey:@(bid)] removeObject:n];
                }
            }
        }
        if(![[_notifications objectForKey:@(bid)] count])
            [_notifications removeObjectForKey:@(bid)];
    }
#endif
}

-(id)getNotification:(NSTimeInterval)eid bid:(int)bid {
#ifndef EXTENSION
    @synchronized(_notifications) {
        NSArray *ns = [NSArray arrayWithArray:[_notifications objectForKey:@(bid)]];
        if(@available(iOS 10, *)) {
            for(UNNotification *n in ns) {
                NSArray *d = [n.request.content.userInfo objectForKey:@"d"];
                if([[d objectAtIndex:1] intValue] == bid && [[d objectAtIndex:2] doubleValue] == eid) {
                    return n;
                }
            }
        } else {
            for(UILocalNotification *n in ns) {
                NSArray *d = [n.userInfo objectForKey:@"d"];
                if([[d objectAtIndex:1] intValue] == bid && [[d objectAtIndex:2] doubleValue] == eid) {
                    return n;
                }
            }
        }
    }
#endif
    return nil;
}

-(void)updateBadgeCount {
#ifndef EXTENSION
    if(@available(iOS 10, *)) {
        [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray *notifications) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                NSUInteger count = 0;
                NSArray *buffers = [[BuffersDataSource sharedInstance] getBuffers];
                NSDictionary *prefs = [[NetworkConnection sharedInstance] prefs];
                NSMutableArray *identifiers = [[NSMutableArray alloc] init];
                
                for(Buffer *b in buffers) {
                    b.extraHighlights = 0;
                }
                
                for(UNNotification *n in notifications) {
                    NSArray *d = [n.request.content.userInfo objectForKey:@"d"];
                    Buffer *b = [[BuffersDataSource sharedInstance] getBuffer:[[d objectAtIndex:1] intValue]];
                    NSTimeInterval eid = [[d objectAtIndex:2] doubleValue];
                    if((!b && [NetworkConnection sharedInstance].state == kIRCCloudStateConnected && [NetworkConnection sharedInstance].ready) || eid <= b.last_seen_eid) {
                        [identifiers addObject:n.request.identifier];
                    } else if(![[EventsDataSource sharedInstance] event:eid buffer:b.bid]) {
                        b.extraHighlights++;
                        CLS_LOG(@"bid%i has notification eid%.0f that's not in the loaded backlog, extraHighlights: %i", b.bid, eid, b.extraHighlights);
                    }
                }
                
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:identifiers];
                
                for(Buffer *b in buffers) {
                    int highlights = [[EventsDataSource sharedInstance] highlightCountForBuffer:b.bid lastSeenEid:b.last_seen_eid type:b.type];
                    if([b.type isEqualToString:@"conversation"] && [[[prefs objectForKey:@"buffer-disableTrackUnread"] objectForKey:[NSString stringWithFormat:@"%i",b.bid]] intValue] == 1)
                        highlights = 0;
                    count += highlights;
                }

                if([UIApplication sharedApplication].applicationIconBadgeNumber != count)
                    CLS_LOG(@"Setting iOS icon badge to %lu", (unsigned long)count);
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [UIApplication sharedApplication].applicationIconBadgeNumber = count;
                    [[NSNotificationCenter defaultCenter] postNotificationName:kIRCCloudEventNotification object:nil userInfo:@{kIRCCloudEventKey:[NSNumber numberWithInt:kIRCEventRefresh]}];
                }];
            }];
        }];
    } else {
        int count = 0;
        for(NSArray *a in _notifications.allValues) {
            count += a.count;
        }
        /*NSArray *buffers = [[BuffersDataSource sharedInstance] getBuffers];
        for(Buffer *b in buffers) {
            count += [[EventsDataSource sharedInstance] highlightCountForBuffer:b.bid lastSeenEid:b.last_seen_eid type:b.type];
        }*/
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if([UIApplication sharedApplication].applicationIconBadgeNumber != count)
                CLS_LOG(@"Setting iOS icon badge to %i", count);
            [UIApplication sharedApplication].applicationIconBadgeNumber = count;
            if(!count)
                [[UIApplication sharedApplication] cancelAllLocalNotifications];
        }];
    }
#endif
}
@end
