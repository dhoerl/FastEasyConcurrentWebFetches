//
//  TestOperation.h
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#import "ConcurrentOperation.h"

#define TIMER_DELAY 0.1

@protocol TestOperationProtocol;

typedef enum { noAction, failAtSetup, failAtStartup, forceSuccess, forceFailure } forceMode;

@interface TestOperation : ConcurrentOperation
@property (nonatomic, weak) id <TestOperationProtocol> delegate;
@property (atomic, assign) forceMode forceAction;
@property (atomic, assign) int succeeded;	// -1 == init, 0 == FAIL, 1 -- SUCCESS
@property (atomic, assign) NSUInteger finishedMsg;
@property (atomic, assign) BOOL fireTimer;
@property (atomic, assign) double delayInMain;

@end
