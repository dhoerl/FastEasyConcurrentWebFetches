//
//  FastEasyConcurrentWebFetchesTests.m
//  FastEasyConcurrentWebFetchesTests
//
//  Created by David Hoerl on 4/20/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

#include <signal.h>
#include <libkern/OSAtomic.h>

#import "FECWF5_Tests.h"

#import "OperationsRunner.h"
#import "TestOperationProtocol.h"
#import "TestOperation5.h"

#define MIN_TEST	0	// Starting test, but 0 always runs
#define MAX_TEST	8	// Last test

#define MAX_OPS		4	// OperationQueue max
#define NUM_OPS		(10*MAX_OPS)	// loops per test, must be multiple of MAX_OPS

#define iCount		1	// loops per test

#if 0	// 0 == no debug, 1 == lots of mesages
#define TLOG(...) NSLog(__VA_ARGS__)
#else
#define TLOG(...)
#endif

#define WAIT_UNTIL(x, y, msg)						\
	for(int iii=0; iii < NUM_OPS*10 && !(x); ++iii)  {	\
		if(!iii) {TLOG(@"WAITING " #y "...");}		\
		usleep(10000);								\
	}												\
	if(!(x)) {										\
		NSLog(@"FAILED ON LOOP %d UNTIL " #y , i);	\
		[self dump];								\
		STAssertTrue((x), (msg));					\
		return;										\
	} else {										\
		TLOG(@"...DONE " #y);						\
	}												\
	while(0)

#define WAIT_WHILE(x, y, msg)						\
	for(int iii=0; iii < NUM_OPS*10 && (x); ++iii)  {	\
		if(!iii) {TLOG(@"WAITING " #y "...");}		\
		usleep(10000);								\
	}												\
	if((x)) {										\
		NSLog(@"FAILED ON LOOP %d WHILE " #y , i);	\
		[self dump];								\
		STAssertFalse((x), (msg));					\
		return;										\
	} else {										\
		TLOG(@"...DONE " #y);						\
	}												\
	while(0)

static void myAlrm(int sig)
{
	//NSLog(@"ALARM!!!!");
}

// //typedef enum {nofailure, failAtSetup, failAtStartup, failAfterFirstMsg, failWithFailureMsg } forceFailure;

@interface FastEasyConcurrentWebFetchesTests () <OperationsRunnerProtocol, TestOperationProtocol>

@end

@interface FastEasyConcurrentWebFetchesTests (OperationsRunner)

- (OperationsRunner *)operationsRunner;				// get the current instance (or create it)
- (void)runOperation:(ConcurrentOperation *)op withMsg:(NSString *)msg;	// to submit an operation
- (BOOL)runOperations:(NSSet *)operations;			// Set of ConcurrentOperation objects with their runMessage set (or not)
- (NSUInteger)operationsCount;						// returns the total number of outstanding operations
- (BOOL)cancelOperations;							// stop all work, will not get any more delegate calls after it returns, returns YES if everything torn down properly
- (void)restartOperations;							// restart things

@end

@implementation FastEasyConcurrentWebFetchesTests
{
	__block int			opFailed, opSucceeded, opNeverRan;
	int32_t				stageCounters[atEnd];

	int					count;
	dispatch_queue_t	queue;
	dispatch_group_t	group;
}

- (void)dealloc
{
	[self cancelOperations];	// you can send this at any time, for instance when the 'Back' button is tapped
}

- (void)setUp
{
    [super setUp];

	OperationsRunner *operationsRunner = [self operationsRunner];
	if(!operationsRunner.delegateQueue) {
		// re-using it should be more stressful than getting a new one each time
		queue = dispatch_queue_create("com.fecw.test", DISPATCH_QUEUE_SERIAL);
		group = dispatch_group_create();
	
		operationsRunner.delegateQueue = queue;
		operationsRunner.delegateGroup = group;
		operationsRunner.maxOps = MAX_OPS;
		assert(operationsRunner.msgDelOn == msgOnSpecificQueue);
		
		// Having ops run slowly is more likely to cause logic errors to show up in testing
		operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_HIGH; // DISPATCH_QUEUE_PRIORITY_BACKGROUND;
		dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
	}
	count = NUM_OPS;

}

- (void)tearDown
{
    // Tear-down code here.
    [self cancelOperations];
	dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [super tearDown];
}

- (void)dump
{
	NSLog(@"OperationsCount        = %d", [self operationsCount]);
	NSLog(@"opFailed               = %d", opFailed);
	NSLog(@"opSucceeded            = %d", opSucceeded);
	NSLog(@"opNeverRan             = %d", opNeverRan);
	NSLog(@"stageCounters[main]    = %d", stageCounters[0]);
	NSLog(@"stageCounters[setup]   = %d", stageCounters[1]);
	NSLog(@"stageCounters[started] = %d", stageCounters[2]);
	NSLog(@"stageCounters[finish]  = %d", stageCounters[3]);
	NSLog(@"stageCounters[exit]    = %d", stageCounters[4]);
}

#if 0 >= MIN_TEST && 0 <= MAX_TEST

- (void)test0
// Verify ops do not complete without a complete/fail message, and that sending complete results in all operations succeeding
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];

		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = forceSuccess;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		WAIT_UNTIL(count == [self adjustOperationsCount:0 atStage:atMain], 1, @"Operations did not start running");

		WAIT_UNTIL(count == (opFailed+opSucceeded+opNeverRan), 2, @"All ops did not complete");
		STAssertEquals(opSucceeded, count, @"All ops should have succeeded");
	}
}
#endif

#if 1 >= MIN_TEST && 1 <= MAX_TEST

- (void)test1
// Verify ops do not complete without a complete/fail message, and that sending failed results in all operations succeeding
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];

		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = forceFailure;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		WAIT_UNTIL(count == [self adjustOperationsCount:0 atStage:atMain], 1, @"Operations did not start running");

		WAIT_UNTIL(count == (opFailed+opSucceeded+opNeverRan), 2, @"All ops did not complete");
		STAssertEquals(opFailed, count, @"All ops should have succeeded");
	}
}
#endif

#if 2 >= MIN_TEST && 2 <= MAX_TEST
// Verify if we canel the apps immediately, everything tears down OK
- (void)test2
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}
		[self cancelOperations];
		
		WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

//NSLog(@"COUNT0=%d", [self adjustOperationsCount:0 atStage:atMain]);
//NSLog(@"COUNT1=%d", [self adjustOperationsCount:0 atStage:atSetup]);
//NSLog(@"COUNT2=%d", [self adjustOperationsCount:0 atStage:atStart]);

		STAssertTrue([self adjustOperationsCount:0 atStage:atMain] <= count, @"Should only have a few");
		STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] <= count, @"Should only have a few");
		STAssertTrue([self adjustOperationsCount:0 atStage:atStart] <= count, @"Should only have a few");
		STAssertEquals(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
		//[self dump];
	}
}
#endif

#if 3 >= MIN_TEST && 3 <= MAX_TEST
// Verify if we canel the apps immediately, force apps to delay starting, everything tears down OK
- (void)test3
{
	for(int i=1; i<=iCount; ++i) {
		//@autoreleasepool
		{
			TLOG(@"TEST %d: ==================================================================================", i);
			[self loopInit];
			for(int j=0; j<count; ++j) {
				TestOperation *t = [TestOperation new];
				t.delegate = self;
				t.delayInMain = TIMER_DELAY * 10 * 1000000.0;
				[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
			}
			BOOL ret = [self cancelOperations];
			STAssertTrue(ret, @"Cancel failed");
			
			WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

			STAssertTrue([self adjustOperationsCount:0 atStage:atMain] == 0, @"Should only have a few at main");
			STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == 0, @"Should never reach setup");
			STAssertTrue([self adjustOperationsCount:0 atStage:atStart] == 0, @"Should never reach start");
			STAssertEquals(opFailed+opSucceeded+opNeverRan, 0, @"Nothing should completed or failed");
			//[self dump];
		}
	}
}
#endif


#if 4 >= MIN_TEST && 4 <= MAX_TEST
// Verify when setup fails the right thing happens
- (void)test4
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = failAtSetup;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}		
		WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

		STAssertTrue([self adjustOperationsCount:0 atStage:atMain] == count, @"All should make main");
		STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		STAssertTrue([self adjustOperationsCount:0 atStage:atStart] == 0, @"Should never reach start");
		STAssertEquals(opNeverRan, count, @"Nothing should completed or failed");
	}
}
#endif

#if 5 >= MIN_TEST && 5 <= MAX_TEST
// Verify when setup fails the right thing happens
- (void)test5
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = failAtStartup;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}		
		WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

		STAssertTrue([self adjustOperationsCount:0 atStage:atMain] == count, @"All should make main");
		STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		STAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"Should never reach start");
		STAssertEquals(opNeverRan, count, @"Nothing should completed or failed");
	}
}
#endif

#if 6 >= MIN_TEST && 6 <= MAX_TEST
// Verify when a short timer goes off and we force a failed message, things cleanup
- (void)test6
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = forceFailure;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}		
		WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

		STAssertTrue([self adjustOperationsCount:0 atStage:atMain] == count, @"All should make main");
		STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		STAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"All should reach start");
		STAssertTrue([self adjustOperationsCount:0 atStage:atFinish] == count, @"All should reach start");
		STAssertEquals(opFailed, count, @"All failed");
	}
}
#endif

#if 7 >= MIN_TEST && 7 <= MAX_TEST
- (void)test7
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = forceSuccess;
			[self runOperation:t withMsg:[NSString stringWithFormat:@"Op %d", j]];
		}		
		WAIT_UNTIL([self operationsCount] == 0, 1, @"Some operation did not cancel");

		STAssertTrue([self adjustOperationsCount:0 atStage:atMain] == count, @"All should make main");
		STAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		STAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"All should reach start");
		STAssertEquals(opSucceeded, count, @"All success");
	}
}
#endif

#if 0
- (BOOL)waitTilRunning
{
	__block int cnt = 0;
	for(int i=0; i<10; ++i) {
		cnt = 0;
		[operationsRunner enumerateOperations:^(ConcurrentOperation *op)
			{
				if(op.isExecuting) {
					dispatch_group_async(group, queue, ^
						{
							++cnt;
						});
				}
			} ];
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		if(cnt == MAX_OPS) break;
		usleep(100000);
	}

	usleep(100000);
	dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

	//STAssertEquals(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
	return cnt == MAX_OPS;
}
#endif

- (int32_t)adjustOperationsCount:(int32_t)val atStage:(registrationStage)stage
{
	int32_t *ptr = &stageCounters[stage];
	int32_t nVal = OSAtomicAdd32(val, ptr);
	return nVal;
}

- (void)loopInit
{
	memset(stageCounters, 0, sizeof(stageCounters));
	//int32_t nVal = OSAtomicAdd32(0, &_DO_NOT_ACCESS_operationsCount);
	//OSAtomicAdd32(-nVal, &_DO_NOT_ACCESS_operationsCount);

	opFailed = 0;
	opSucceeded = 0;
	opNeverRan = 0;

	[self restartOperations];
}

- (void)register:(id)op atStage:(registrationStage)stage
{
//NSLog(@"register %d", stage);
	[self adjustOperationsCount:1 atStage:stage];
}

- (void)operationFinished:(ConcurrentOperation *)op count:(NSUInteger)remainingOps	// on queue
{
	TestOperation *t = (TestOperation *)op;

	switch(t.succeeded) {
	default:
	case -1:
		++opFailed;
		break;
	case 0:
		++opNeverRan;
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
		sel == @selector(cancelOperations)		||
		sel == @selector(restartOperations)		||
		sel == @selector(operationsRunner)
	) {
		static BOOL myKey;
		id obj = objc_getAssociatedObject(self, &myKey);
		if(!obj) {
			if(sel == @selector(cancelOperations)) {
				// cancel sent in say dealloc, don't create an object just to release it
				obj = [OperationsRunner class];
			} else {
				// Object only created if needed. NOT THREAD SAFE (if you need that use a dispatch semaphone to insure only one object created
				obj = [[OperationsRunner alloc] initWithDelegate:self];
				objc_setAssociatedObject(self, &myKey, obj, OBJC_ASSOCIATION_RETAIN);
				{
					// Set priorities once, or optionally you can ask [self operationsRunner] to get/create the item, and set/change these dynamically
					// OperationsRunner *OperationsRunner = (OperationsRunner *)obj;
					// operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;	// for example
					// operationsRunner.maxOps = 4;										// for example
					// operationsRunner.mSecCancelDelay = 10;							// for example
				}
			}
		}
		return obj;
	} else {
		return [super forwardingTargetForSelector:sel];
	}
}

@end


