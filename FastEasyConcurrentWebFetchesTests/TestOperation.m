//
//  TestOperation.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

//#include <signal.h>

#import "TestOperationProtocol.h"

#import "TestOperation.h"

@interface TestOperation ()

@end

static void myAlrm(int sig)
{
	NSLog(@"myAlrm!!!!");
}

@implementation TestOperation
{
	NSTimer *t;
	NSUInteger timerMax;
}

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

	ret = self.forceAction == failAtStartup ? NO : ret;
	
	if(ret) {
		t = [NSTimer scheduledTimerWithTimeInterval:TIMER_DELAY target:self selector:@selector(myTimer:) userInfo:nil repeats:YES];
	}
	return ret;
}

- (void)completed
{
	[super completed];
	
	self.succeeded = 1;
}

- (void)finish
{
	[super finish];

	[t invalidate], t = nil;

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
	
	// Really important to do this if you use a timer in a super class. Ask me how I know this.
	[t invalidate], t = nil;
	NSLog(@"cancel timer");
}

- (void)myTimer:(NSTimer *)timer
{
	switch(self.forceAction) {
	case forceSuccess:
		[self completed];
		[timer invalidate];
		break;

	case forceFailure:
		[self failed];
		[timer invalidate];
		break;
		
	default:
		if(++timerMax == 100) {
			[self completed];
			[timer invalidate];
		}
		break;
	}
}

@end

