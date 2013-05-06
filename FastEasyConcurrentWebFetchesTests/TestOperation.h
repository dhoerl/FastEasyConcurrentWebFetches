//
//  TestOperation.h
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#import "WebFetcher.h"

#define TIMER_DELAY 0.1

@protocol TestOperationProtocol;

@interface TestOperation : WebFetcher
@property (nonatomic, weak) id <TestOperationProtocol> delegate;
@property (atomic, assign) int succeeded;	// -1 == init, 0 == FAIL, 1 -- SUCCESS
@property (atomic, assign) NSUInteger finishedMsg;
@property (atomic, assign) BOOL fireTimer;
@property (atomic, assign) double delayInMain;

@end
