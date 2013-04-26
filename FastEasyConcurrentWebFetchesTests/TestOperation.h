//
//  TestOperation.h
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#import "ConcurrentOperation.h"

@protocol FastEasyConcurrentWebFetchesProtocol;

typedef enum { nofailure, failAtSetup, failAtStartup, failAfterFirstMsg, failWithFailureMsg } forceFailure;

@interface TestOperation : ConcurrentOperation
@property (nonatomic, weak) id <FastEasyConcurrentWebFetchesProtocol> delegate;
@property (atomic, assign) forceFailure forceFailure;
@property (atomic, assign) int succeeded;	// -1 == init, 0 == FAIL, 1 -- SUCCESS
@property (atomic, assign) NSUInteger finishedMsg;
@property (atomic, assign) BOOL delayInMain;

@end
