//
//  TestOperation.h
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
#import "WebFetcher6.h"
#else
#import "WebFetcher.h"
#endif

#define TIMER_DELAY 0.1

@protocol TestOperationProtocol;

@interface TestOperation : FECWF_WEBFETCHER
@property (nonatomic, weak) id <TestOperationProtocol> delegate;
@property (atomic, assign) int succeeded;	// -1 == init, 0 == FAIL, 1 -- SUCCESS
@property (atomic, assign) NSUInteger finishedMsg;
@property (atomic, assign) BOOL fireTimer;
@property (atomic, assign) double delayInMain;

@end
