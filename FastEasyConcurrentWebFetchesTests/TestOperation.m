//
//  TestOperation.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#include <math.h>

#ifndef UNIT_TESTING
#define UNIT_TESTING 1
#endif

#import "TestOperationProtocol.h"
#import "TestOperation.h"

@interface TestOperation ()

@end

@implementation TestOperation


- (id)setup
{
	// Idea is to artificially create some startup delay
	for(int i=0; i<100 && !self.isCancelled && isnormal(self.delayInMain); ++i) {
		usleep(self.delayInMain/100.0);
	}
	if(self.isCancelled) {
		return nil;
	}

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
	{
		finishBlock b = self.finalBlock;
		__weak __typeof__(self) weakSelf = self;
		self.finalBlock = ^(FECWF_WEBFETCHER *op, BOOL succeeded)
							{
//NSLog(@"B=%@ succeeded=%d", b ? @"YES" : @"NO", succeeded);
								__typeof__(self) strongSelf = weakSelf;
								[strongSelf.delegate register:strongSelf atStage:atExit];
								if(b) b(op, succeeded);
							};
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
//NSLog(@"FAILED");
	self.succeeded = -1;
}

- (void)cancel
{
	[super cancel];

}

@end

