//
//  TestOperation.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#import "FastEasyConcurrentWebFetchesProtocol.h"

#import "TestOperation.h"

@interface TestOperation ()

@end

@implementation TestOperation
{
	NSTimer *t;
}

- (void)main
{
	if(self.delayInMain) usleep(100000);	// 100ms

	[super main];
}

- (id)setup
{
	id foo = [super setup];

	[self.delegate register:self];

	t = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(myTimer:) userInfo:nil repeats:YES];
//NSLog(@"FUCK A DUCK %@", self);
	return self.forceFailure == failAtSetup ? nil : foo;
}

- (BOOL)start:(id)setupObject
{
	BOOL ret = [super start:setupObject];

	return self.forceFailure == failAtSetup ? NO : ret;
}

- (void)completed
{
	self.succeeded = 1;

	[super completed];
}

- (void)finish
{
//NSLog(@"CLEAR FUCK A DUCK %@", self);
	[t invalidate], t = nil;

	++self.finishedMsg;
	
	[super finish];
}

- (void)failed
{
	self.succeeded = 0;
	
	[super failed];
}

- (void)myTimer:(NSTimer *)timer
{
	if(self.forceFailure == failAfterFirstMsg) {
		[self performBlock:^(ConcurrentOperation *op) { [op failed]; }];
		//[self performSelector:@selector(failed) onThread:self.thread withObject:nil waitUntilDone:NO];
	}
}

@end

