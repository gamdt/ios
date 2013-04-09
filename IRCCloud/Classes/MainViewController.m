//
//  MainViewController.m
//  IRCCloud
//
//  Created by Sam Steele on 2/25/13.
//  Copyright (c) 2013 IRCCloud, Ltd. All rights reserved.
//

#import "MainViewController.h"
#import "NetworkConnection.h"

@implementation MainViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _cidToOpen = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if(_contentView != nil) {
        [(UIScrollView *)self.view addSubview:_contentView];
    } else {
        _contentView = self.view;
    }
    _startHeight = [UIScreen mainScreen].applicationFrame.size.height - 44;
    self.navigationItem.leftBarButtonItem = _navItem.leftBarButtonItem;
    self.navigationItem.rightBarButtonItem = _navItem.rightBarButtonItem;
    //TODO: resize if the keyboard is visible
    //TODO: check the user info for the last BID
    [self bufferSelected:[BuffersDataSource sharedInstance].firstBid];
}

- (void)handleEvent:(NSNotification *)notification {
    kIRCEvent event = [[notification.userInfo objectForKey:kIRCCloudEventKey] intValue];
    Buffer *b = nil;
    IRCCloudJSONObject *o = nil;
    switch(event) {
        case kIRCEventLinkChannel:
            o = notification.object;
            if(_cidToOpen == o.cid && [[o objectForKey:@"invalid_chan"] isEqualToString:_bufferToOpen]) {
                _bufferToOpen = [o objectForKey:@"valid_chan"];
                b = [[BuffersDataSource sharedInstance] getBuffer:o.bid];
            }
        case kIRCEventMakeBuffer:
            if(!b)
                b = notification.object;
            if(_cidToOpen == b.cid && [b.name isEqualToString:_bufferToOpen] && ![_buffer.name isEqualToString:_bufferToOpen]) {
                [self bufferSelected:b.bid];
                _bufferToOpen = nil;
                _cidToOpen = -1;
            } else if(_buffer.bid == -1 && b.cid == _buffer.cid && [b.name isEqualToString:_buffer.name]) {
                [self bufferSelected:b.bid];
                _bufferToOpen = nil;
                _cidToOpen = -1;
            }
            break;
        case kIRCEventOpenBuffer:
            o = notification.object;
            _bufferToOpen = [o objectForKey:@"name"];
            _cidToOpen = o.cid;
            b = [[BuffersDataSource sharedInstance] getBufferWithName:_bufferToOpen server:_cidToOpen];
            if(b != nil && ![b.name isEqualToString:_buffer.name]) {
                [self bufferSelected:b.bid];
                _bufferToOpen = nil;
                _cidToOpen = -1;
            }
            break;
        case kIRCEventUserInfo:
        case kIRCEventPart:
            [self _updateUserListVisibility];
            break;
        default:
            break;
    }
}

-(void)_showConnectingView {
    if(_connectingView.hidden) {
        CGRect frame = _connectingView.frame;
        frame.origin.y = -frame.size.height;
        _connectingView.frame = frame;
        _connectingView.hidden = NO;
        frame.origin.y = 0;
        [UIView animateWithDuration:0.3
                         animations:^{_connectingView.frame = frame;}
                         completion:nil];
    }
}

-(void)_hideConnectingView {
    if(!_connectingView.hidden) {
        CGRect frame = _connectingView.frame;
        frame.origin.y = 0;
        _connectingView.frame = frame;
        _connectingView.hidden = NO;
        frame.origin.y = -frame.size.height;
        [UIView animateWithDuration:0.3
                         animations:^{_connectingView.frame = frame;}
                         completion:^(BOOL finished){ _connectingView.hidden = YES; }];
    }
}

-(void)connectivityChanged:(NSNotification *)notification {
    switch([NetworkConnection sharedInstance].state) {
        case kIRCCloudStateConnecting:
            [self _showConnectingView];
            _connectingStatus.text = @"Connecting";
            [_connectingActivity startAnimating];
            _connectingActivity.hidden = NO;
            _connectingProgress.progress = 0;
            _connectingProgress.hidden = YES;
            _connectingError.text = @"";
            break;
        case kIRCCloudStateDisconnected:
            if([NetworkConnection sharedInstance].reconnectTimestamp > 0) {
                [_connectingStatus setText:[NSString stringWithFormat:@"Reconnecting in %0.f seconds", [NetworkConnection sharedInstance].reconnectTimestamp - [[NSDate date] timeIntervalSince1970]]];
                _connectingActivity.hidden = NO;
                [_connectingActivity startAnimating];
                _connectingProgress.progress = 0;
                _connectingProgress.hidden = YES;
                [self performSelector:@selector(connectivityChanged:) withObject:nil afterDelay:1];
            } else {
                _connectingStatus.text = @"Disconnected";
                _connectingActivity.hidden = YES;
                _connectingProgress.progress = 0;
                _connectingProgress.hidden = YES;
                _connectingError.text = @"";
            }
        case kIRCCloudStateDisconnecting:
            [self _showConnectingView];
        case kIRCCloudStateConnected:
            [_connectingActivity stopAnimating];
            break;
    }
}

-(void)backlogStarted:(NSNotification *)notification {
    [_connectingStatus setText:@"Loading"];
    _connectingActivity.hidden = YES;
    [_connectingActivity stopAnimating];
    _connectingProgress.progress = 0;
    _connectingProgress.hidden = NO;
}

-(void)backlogProgress:(NSNotification *)notification {
    [_connectingProgress setProgress:[notification.object floatValue] animated:YES];
}

-(void)backlogCompleted:(NSNotification *)notification {
    [self _hideConnectingView];
    if(!_buffer) {
        //TODO: check the user info for the last BID
        [self bufferSelected:[BuffersDataSource sharedInstance].firstBid];
    }
}

-(void)keyboardWillShow:(NSNotification*)notification {
    NSArray *rows = [_eventsView.tableView indexPathsForVisibleRows];
    CGSize keyboardSize = [self.view convertRect:[[notification.userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue] toView:nil].size;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationCurve:[[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
    [UIView setAnimationDuration:[[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    
    CGRect frame = self.view.frame;
    frame.size.height -= keyboardSize.height;
    self.view.frame = frame;
    [_eventsView.tableView scrollToRowAtIndexPath:[rows lastObject] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    
    [UIView commitAnimations];

    if([self.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)self.view;
        scrollView.contentSize = CGSizeMake(_contentView.frame.size.width,frame.size.height);
    }
}

-(void)keyboardWillBeHidden:(NSNotification*)notification {
    NSArray *rows = [_eventsView.tableView indexPathsForVisibleRows];
    CGSize keyboardSize = [self.view convertRect:[[notification.userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue] toView:nil].size;
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationCurve:[[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
    [UIView setAnimationDuration:[[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    
    CGRect frame = self.view.frame;
    frame.size.height += keyboardSize.height;
    self.view.frame = frame;
    [_eventsView.tableView scrollToRowAtIndexPath:[rows lastObject] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    
    [UIView commitAnimations];
    
    if([self.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)self.view;
        scrollView.contentSize = CGSizeMake(_contentView.frame.size.width,frame.size.height);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [_buffersView viewDidAppear:animated];
    [_usersView viewDidAppear:animated];
    [_eventsView viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [_buffersView viewDidDisappear:animated];
    [_usersView viewDidDisappear:animated];
    [_eventsView viewDidDisappear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [_message resignFirstResponder];
    CGRect frame = self.view.frame;
    frame.size.height = _startHeight;
    self.view.frame = frame;
    if([self.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)self.view;
        scrollView.contentSize = CGSizeMake(_contentView.frame.size.width,frame.size.height);
    }
    [self connectivityChanged:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleEvent:) name:kIRCCloudEventNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backlogStarted:)
                                                 name:kIRCCloudBacklogStartedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backlogProgress:)
                                                 name:kIRCCloudBacklogProgressNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backlogCompleted:)
                                                 name:kIRCCloudBacklogCompletedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(connectivityChanged:)
                                                 name:kIRCCloudConnectivityNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    [_buffersView viewWillAppear:animated];
    [_usersView viewWillAppear:animated];
    [_eventsView viewWillAppear:animated];
    if([self.view isKindOfClass:[UIScrollView class]]) {
        ((UIScrollView *)self.view).contentSize = _contentView.bounds.size;
        ((UIScrollView *)self.view).contentOffset = CGPointMake(220, 0);
    }
    NSString *session = [[NSUserDefaults standardUserDefaults] stringForKey:@"session"];
    if(([NetworkConnection sharedInstance].state == kIRCCloudStateDisconnected || [NetworkConnection sharedInstance].state == kIRCCloudStateDisconnecting) && session != nil && [session length] > 0)
        [[NetworkConnection sharedInstance] connect];
}

- (void)viewWillDisappear:(BOOL)animated {
    [_buffersView viewWillDisappear:animated];
    [_usersView viewWillDisappear:animated];
    [_eventsView viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(IBAction)sendButtonPressed:(id)sender {
    [[NetworkConnection sharedInstance] say:_message.text to:_buffer.name cid:_buffer.cid];
    _message.text = @"";
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendButtonPressed:textField];
    return YES;
}

-(void)bufferSelected:(int)bid {
    TFLog(@"BID selected: %i", bid);
    _buffer = [[BuffersDataSource sharedInstance] getBuffer:bid];
    if([_buffer.type isEqualToString:@"console"]) {
        Server *s = [[ServersDataSource sharedInstance] getServer:_buffer.cid];
        if(s.name.length)
            self.navigationItem.title = s.name;
        else
            self.navigationItem.title = s.hostname;
    } else {
        self.navigationItem.title = _buffer.name;
    }
    [_buffersView setBuffer:_buffer];
    [_usersView setBuffer:_buffer];
    [_eventsView setBuffer:_buffer];
    [self _updateUserListVisibility];
}

-(void)_updateUserListVisibility {
    if([self.view isKindOfClass:[UIScrollView class]]) {
        [((UIScrollView *)self.view) scrollRectToVisible:_eventsView.tableView.frame animated:YES];
        if([_buffer.type isEqualToString:@"channel"] && [[ChannelsDataSource sharedIntance] channelForBuffer:_buffer.bid] && !([NetworkConnection sharedInstance].prefs && [[[[NetworkConnection sharedInstance].prefs objectForKey:@"channel-hiddenMembers"] objectForKey:[NSString stringWithFormat:@"%i",_buffer.bid]] boolValue])) {
            self.navigationItem.rightBarButtonItem = _navItem.rightBarButtonItem;
            CGSize size = ((UIScrollView *)self.view).contentSize;
            size.width = [UIScreen mainScreen].bounds.size.width + _buffersView.view.bounds.size.width + _usersView.view.bounds.size.width;
            ((UIScrollView *)self.view).contentSize = size;
        } else {
            self.navigationItem.rightBarButtonItem = nil;
            CGSize size = ((UIScrollView *)self.view).contentSize;
            size.width = [UIScreen mainScreen].bounds.size.width + _buffersView.view.bounds.size.width;
            ((UIScrollView *)self.view).contentSize = size;
        }
    } else {
        if([_buffer.type isEqualToString:@"channel"] && [[ChannelsDataSource sharedIntance] channelForBuffer:_buffer.bid] && !([NetworkConnection sharedInstance].prefs && [[[[NetworkConnection sharedInstance].prefs objectForKey:@"channel-hiddenMembers"] objectForKey:[NSString stringWithFormat:@"%i",_buffer.bid]] boolValue])) {
            CGRect frame = _eventsView.view.frame;
            frame.size.width = [UIScreen mainScreen].bounds.size.height - _buffersView.view.bounds.size.width - _usersView.view.bounds.size.width;
            _eventsView.view.frame = frame;
            frame = _message.superview.frame;
            frame.size.width = [UIScreen mainScreen].bounds.size.height - _buffersView.view.bounds.size.width - _usersView.view.bounds.size.width;
            _message.superview.frame = frame;
            _usersView.view.hidden = NO;
        } else {
            CGRect frame = _eventsView.view.frame;
            frame.size.width = [UIScreen mainScreen].bounds.size.height - _buffersView.view.bounds.size.width;
            _eventsView.view.frame = frame;
            frame = _message.superview.frame;
            frame.size.width = [UIScreen mainScreen].bounds.size.height - _buffersView.view.bounds.size.width;
            _message.superview.frame = frame;
            _usersView.view.hidden = YES;
        }
    }
}

-(void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _startX = scrollView.contentOffset.x;
}

-(void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if(!decelerate) {
        [self scrollViewWillBeginDecelerating:scrollView];
    }
}

-(IBAction)usersButtonPressed:(id)sender {
    UIScrollView *scrollView = (UIScrollView *)self.view;
    if(scrollView.contentOffset.x == _eventsView.tableView.frame.origin.x || scrollView.contentOffset.x == _buffersView.tableView.frame.origin.x) {
        [scrollView scrollRectToVisible:_usersView.tableView.frame animated:YES];
    } else {
        [scrollView scrollRectToVisible:_eventsView.tableView.frame animated:YES];
    }
}

-(IBAction)listButtonPressed:(id)sender {
    UIScrollView *scrollView = (UIScrollView *)self.view;
    if(scrollView.contentOffset.x == _buffersView.tableView.frame.origin.x) {
        [scrollView scrollRectToVisible:_eventsView.tableView.frame animated:YES];
    } else {
        [scrollView scrollRectToVisible:_buffersView.tableView.frame animated:YES];
    }
}

-(void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    int buffersDisplayWidth = _buffersView.tableView.bounds.size.width;
    int usersDisplayWidth = _usersView.tableView.bounds.size.width;
    
    if(abs(_startX - scrollView.contentOffset.x) > buffersDisplayWidth / 4) { //If they've dragged a drawer more than 25% on screen, snap the drawer onto the screen
        if(_startX < buffersDisplayWidth + usersDisplayWidth / 4 && scrollView.contentOffset.x < _startX) {
            [scrollView setContentOffset:CGPointMake(0,0) animated:YES];
            //TODO: set the buffer swipe tip flag
        } else if(_startX >= buffersDisplayWidth && scrollView.contentOffset.x > _startX) {
            [scrollView setContentOffset:CGPointMake(buffersDisplayWidth + usersDisplayWidth,0) animated:YES];
            //TODO: set the buffer swipe tip flag
        } else {
            [scrollView setContentOffset:CGPointMake(buffersDisplayWidth,0) animated:YES];
        }
    } else { //Snap back
        if(_startX < buffersDisplayWidth)
            [scrollView setContentOffset:CGPointMake(0,0) animated:YES];
        else if(_startX > buffersDisplayWidth + usersDisplayWidth / 4)
            [scrollView setContentOffset:CGPointMake(buffersDisplayWidth + usersDisplayWidth,0) animated:YES];
        else
            [scrollView setContentOffset:CGPointMake(buffersDisplayWidth,0) animated:YES];
    }
    _startX = 0;
}

-(void)rowSelected:(Event *)event {
    [_message resignFirstResponder];
}

-(void)userSelected:(NSString *)nick rect:(CGRect)rect {
    _selectedUser = [[UsersDataSource sharedInstance] getUser:nick cid:_buffer.cid];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@\n(%@)",_selectedUser.nick,_selectedUser.hostmask] delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:@"Whois…"];
    [sheet addButtonWithTitle:@"Send a message"];
    [sheet addButtonWithTitle:@"Mention"];
    [sheet addButtonWithTitle:@"Invite to channel…"];
    [sheet addButtonWithTitle:@"Ignore"];
    if([_buffer.type isEqualToString:@"channel"]) {
        User *me = [[UsersDataSource sharedInstance] getUser:[[ServersDataSource sharedInstance] getServer:_buffer.cid].nick cid:_buffer.cid bid:_buffer.bid];
        if([me.mode rangeOfString:@"q"].location != NSNotFound || [me.mode rangeOfString:@"a"].location != NSNotFound || [me.mode rangeOfString:@"o"].location != NSNotFound) {
            if([_selectedUser.mode rangeOfString:@"o"].location != NSNotFound)
                [sheet addButtonWithTitle:@"Deop"];
            else
                [sheet addButtonWithTitle:@"Op"];
        }
        if([me.mode rangeOfString:@"q"].location != NSNotFound || [me.mode rangeOfString:@"a"].location != NSNotFound || [me.mode rangeOfString:@"o"].location != NSNotFound || [me.mode rangeOfString:@"h"].location != NSNotFound) {
            [sheet addButtonWithTitle:@"Kick…"];
            [sheet addButtonWithTitle:@"Ban…"];
        }
    }
    
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
        [sheet showInView:self.view];
    } else {
        [sheet showFromRect:rect inView:_usersView.tableView animated:NO];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(buttonIndex != -1) {
        NSString *action = [actionSheet buttonTitleAtIndex:buttonIndex];
        
        if([action isEqualToString:@"Send a message"]) {
            Buffer *b = [[BuffersDataSource sharedInstance] getBufferWithName:_selectedUser.nick server:_buffer.cid];
            if(b) {
                [self bufferSelected:b.bid];
            } else {
                b = [[Buffer alloc] init];
                b.cid = _buffer.cid;
                b.bid = -1;
                b.name = _selectedUser.nick;
                b.type = @"conversation";
                _buffer = b;
                self.navigationItem.title = _selectedUser.nick;
                [_buffersView setBuffer:b];
                [_usersView setBuffer:b];
                [_eventsView setBuffer:b];
                [self _updateUserListVisibility];
            }
        } else if([action isEqualToString:@"Op"]) {
            [[NetworkConnection sharedInstance] mode:[NSString stringWithFormat:@"+o %@",_selectedUser.nick] chan:_buffer.name cid:_buffer.cid];
        } else if([action isEqualToString:@"Deop"]) {
            [[NetworkConnection sharedInstance] mode:[NSString stringWithFormat:@"-o %@",_selectedUser.nick] chan:_buffer.name cid:_buffer.cid];
        }
    }
}
@end
