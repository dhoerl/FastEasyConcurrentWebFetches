//
//  TestOperation.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#import "TestOperationProtocol.h"
#import "TestOperation.h"

@interface TestOperation ()

@end

@implementation TestOperation
{
	//NSTimer *t;
	//NSUInteger timerMax;
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED < 60000
- (void)main
{
	// Idea is to artificially create some startup delay
	for(int i=0; i<100 && !self.isCancelled && self.delayInMain; ++i) {
		usleep(self.delayInMain/100.0);
	}
	if(self.isCancelled) return;

	[self.delegate register:self atStage:atMain];

	[super main];

	[self.delegate register:self atStage:atExit];
}
#endif

- (id)setup
{
	[self.delegate register:self atStage:atSetup];
	
	id foo = [super setup];

	return self.forceAction == failAtSetup ? nil : foo;
}

- (BOOL)start:(id)setupObject
{
	[self.delegate register:self atStage:atStart];
	
	BOOL ret = [super start:setupObject];

	BOOL ret2 = self.forceAction == failAtStartup ? NO : ret;
	if(!ret2 && ret) {
		[self finish];
	}
	return ret2;
}

- (void)completed
{
	[super completed];
	
	self.succeeded = 1;
}

- (void)finish
{
	[super finish];

	++self.finishedMsg;

	[self.delegate register:self atStage:atFinish];
}

- (void)failed
{
	[super failed];

	self.succeeded = -1;
}

- (void)cancel
{
	[super cancel];

}

@end

