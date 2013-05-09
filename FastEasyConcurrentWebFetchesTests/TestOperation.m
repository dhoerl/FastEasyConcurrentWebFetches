//
//  TestOperation.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#include <math.h>

#import "TestOperationProtocol.h"
#import "TestOperation.h"

@interface TestOperation ()

@end

@implementation TestOperation

#if __IPHONE_OS_VERSION_MIN_REQUIRED < 60000
- (void)main
{
	[super main];

	[self.delegate register:self atStage:atExit];
}
#endif

- (id)setup
{
	// Idea is to artificially create some startup delay
	for(int i=0; i<100 && !self.isCancelled && isnormal(self.delayInMain); ++i) {
		usleep(self.delayInMain/100.0);
	}
	if(self.isCancelled) return nil;

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
	self.succeeded = 1;	// race condition - must do first

	[super completed];
}

- (void)finish
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
	finishBlock b = self.finalBlock;
	__weak __typeof__(self) weakSelf = self;
	self.finalBlock = ^(FECWF_WEBFETCHER *op)
						{
							__typeof__(self) strongSelf = weakSelf;
							[strongSelf.delegate register:strongSelf atStage:atExit];
							if(b) b(op);
						};
#endif

	[super finish];

	++self.finishedMsg;

	[self.delegate register:self atStage:atFinish];
}

- (void)failed
{
	self.succeeded = -1;	// race condition
	
	[super failed];
}

- (void)cancel
{
	[super cancel];

}

@end

