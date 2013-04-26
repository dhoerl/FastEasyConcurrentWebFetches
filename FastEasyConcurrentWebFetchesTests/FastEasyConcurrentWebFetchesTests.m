//
//  FastEasyConcurrentWebFetchesTests.m
//  FastEasyConcurrentWebFetchesTests
//
//  Created by David Hoerl on 4/20/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#include <signal.h>
#include <libkern/OSAtomic.h>

#import "FastEasyConcurrentWebFetchesTests.h"
#import "FastEasyConcurrentWebFetchesProtocol.h"

#import "OperationsRunner.h"
#import "TestOperation.h"


#define MIN_TEST	0	// Starting test, but 0 always runs
#define MAX_TEST	8	// Last test

#define MAX_OPS		10	// OperationQueue max

#define iCount		2	// loops per test
#define numOps		25	// loops per test

#if 0	// 0 == no debug, 1 == lots of mesages
#define TLOG(...) NSLog(__VA_ARGS__)
#else
#define TLOG(...)
#endif

#define WAIT_UNTIL(x, y, msg)						\
	for(int j=0; j < 10*10 && !(x); ++j)  {			\
		if(!j) TLOG(@"WAITING " #y "...");			\
		usleep(100000);								\
	}												\
	if(!(x)) {										\
		NSLog(@"FAILED ON LOOP %d UNTIL " #y , i);	\
		STAssertTrue((x), (msg));						\
		return;										\
	} else											\
		TLOG(@"...DONE " #y)

#define WAIT_WHILE(x, y, msg)						\
	for(int j=0; j < 10*10 && (x); ++j)  {			\
		if(!j) TLOG(@"WAITING " #y "...");			\
		usleep(100000);								\
	}												\
	if((x)) {										\
		NSLog(@"FAILED ON LOOP %d WHILE " #y , i);	\
		STAssertFalse((x), (msg));					\
		return;										\
	} else											\
		TLOG(@"...DONE " #y)

static void myAlrm(int sig)
{
	//NSLog(@"ALARM!!!!");
}

// //typedef enum {nofailure, failAtSetup, failAtStartup, failAfterFirstMsg, failWithFailureMsg } forceFailure;

@interface FastEasyConcurrentWebFetchesTests () <OperationsRunnerProtocol, FastEasyConcurrentWebFetchesProtocol>

@end

@interface FastEasyConcurrentWebFetchesTests (OperationsRunner)

- (void)runOperation:(ConcurrentOperation *)op withMsg:(NSString *)msg;	// to submit an operation
- (BOOL)runOperations:(NSSet *)operations;	// Set of ConcurrentOperation objects with their runMessage set (or not)

- (void)enumerateOperations:(void(^)(ConcurrentOperation *op))b;		// in some very special cases you may need this (I did)
- (NSUInteger)operationsCount;				// returns the total number of outstanding operations

@end

@implementation FastEasyConcurrentWebFetchesTests
{
	OperationsRunner	*operationsRunner;
	__block int			opFailed, opSucceeded;
	int32_t				_DO_NOT_ACCESS_operationsCount;

	dispatch_queue_t	queue;
	dispatch_group_t	group;
}

- (void)dealloc
{
	[operationsRunner cancelOperations];	// you can send this at any time, for instance when the 'Back' button is tapped
}

- (void)setUp
{
    [super setUp];
	
	if(!operationsRunner) {
		// re-using it should be more stressful than getting a new one each time
		
		queue = dispatch_queue_create("com.fecw.test", DISPATCH_QUEUE_SERIAL);
		group = dispatch_group_create();
	
		operationsRunner = [[OperationsRunner alloc] initWithDelegate:self];
		operationsRunner.delegateQueue = queue;
		operationsRunner.delegateGroup = group;
		operationsRunner.maxOps = MAX_OPS;
		assert(operationsRunner.msgDelOn == msgOnSpecificQueue);
		
		// Having ops run slowly is more likely to cause logic errors to show up in testing
		operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
		dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
	}
}

- (void)tearDown
{
    // Tear-down code here.
    [operationsRunner cancelOperations];
	dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [super tearDown];
}

// Verify ops do not complete without a complete/fail message, and that sending complete results in all operations succeeding
- (void)test0
{
	int count = numOps;
	int tstCount = numOps > MAX_OPS ? MAX_OPS : count;
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		WAIT_UNTIL(tstCount == [self adjustOperationsCount:0], 1, @"Operations did not start running");

		BOOL ret = [self waitTilRunning:count];
		if(!ret) break;

		WAIT_UNTIL([self adjustOperationsCount:0] == tstCount, 3, @"Operations did not start running");
		
		[self enumerateOperations:^(ConcurrentOperation *op)
			{
				[op performBlock:^(ConcurrentOperation *op) { [op completed]; }];
			} ];
		WAIT_UNTIL(tstCount == (opFailed+opSucceeded), 2, @"All ops did not complete");
		STAssertEquals(opSucceeded, tstCount, @"All ops should have succeeded");

		[operationsRunner cancelOperations];
	}
}

// Verify ops do not complete without a complete/fail message, and that sending failed results in all operations succeeding
- (void)test1
{
	int count = numOps;
	int tstCount = numOps > MAX_OPS ? MAX_OPS : count;
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		WAIT_UNTIL(tstCount == [self adjustOperationsCount:0], 1, @"Operations did not start running");

		BOOL ret = [self waitTilRunning:count];
		if(!ret) break;
		
		[self enumerateOperations:^(ConcurrentOperation *op)
			{
				[op performBlock:^(ConcurrentOperation *op) { [op failed]; }];
				//[op performSelector:@selector(failed) onThread:op.thread withObject:nil waitUntilDone:NO];
			} ];
		WAIT_UNTIL(tstCount == (opFailed+opSucceeded), 2, @"All ops did not complete");
		STAssertEquals(opFailed, tstCount, @"All ops should have failed");

		[operationsRunner cancelOperations];
	}
}

// Verify when setup fails the right thing happens
- (void)test2
{
	int count = numOps;
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.delayInMain = YES;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		[operationsRunner cancelOperations];
		
		WAIT_UNTIL([self adjustOperationsCount:0] == 0, 1, @"Some operation got to setup, should not have");
		
		//STAssertEquals((int)[self operationsCount], 0, @"All ops should have just gone away");
		STAssertEquals(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
	}
}

- (BOOL)waitTilRunning:(int)count
{
	__block int cnt = 0;
	for(int i=0; i<10; ++i) {
		cnt = 0;
		[self enumerateOperations:^(ConcurrentOperation *op)
			{
				if(op.isExecuting) {
					dispatch_group_async(group, queue, ^
						{
							++cnt;
						});
				}
			} ];
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		if(cnt == count) break;
		usleep(100000);
	}

	usleep(100000);
	dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

	STAssertEquals(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
	return (opFailed+opSucceeded) == 0;
}

- (int32_t)adjustOperationsCount:(int32_t)val
{
	int32_t nVal = OSAtomicAdd32(val, &_DO_NOT_ACCESS_operationsCount);
	return nVal;
}

- (void)loopInit
{
	int32_t nVal = OSAtomicAdd32(0, &_DO_NOT_ACCESS_operationsCount);
	OSAtomicAdd32(-nVal, &_DO_NOT_ACCESS_operationsCount);

	opFailed = 0;
	opSucceeded = 0;
}

- (void)register:(id)op
{
	[self adjustOperationsCount:1];
}

- (void)operationFinished:(ConcurrentOperation *)op count:(NSUInteger)remainingOps	// on queue
{
	TestOperation *t = (TestOperation *)op;

	switch(t.succeeded) {
	default:
	case -1:
		STAssertTrue(NO, @"Returned unitialized status");
		break;
	case 0:
		++opFailed;
		break;
	case 1:
		++opSucceeded;
		break;
	}

}

- (id)forwardingTargetForSelector:(SEL)sel
{
	if(
		sel == @selector(runOperation:withMsg:)	|| 
		sel == @selector(runOperations:)		||
		sel == @selector(operationsCount)		||
		sel == @selector(enumerateOperations:)
	) {
		if(!operationsRunner) {
			// Object only created if needed
			operationsRunner = [[OperationsRunner alloc] initWithDelegate:self];
			// operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND; // initial value, default is DISPATCH_QUEUE_PRIORITY_DEFAULT
			// operationsRunner.maxOps = 4; // initial value if desired, default is infinite
		}
		return operationsRunner;
	} else {
		return [super forwardingTargetForSelector:sel];
	}
}

@end


