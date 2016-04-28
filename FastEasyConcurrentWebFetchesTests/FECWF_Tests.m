//
//  FastEasyConcurrentWebFetchesTests.m
//  FastEasyConcurrentWebFetchesTests
//
//  Created by David Hoerl on 4/20/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

@import Foundation;

//@import FECWF;

#include <signal.h>
#include <libkern/OSAtomic.h>

#import "WebFetcher.h"

#import "FECWF_Tests.h"

#import "OperationsRunner.h"
#import "OperationsRunnerProtocol.h"

#import "TestOperationProtocol.h"
#import "TestOperation.h"


#define MIN_TEST	0				// Starting test #
#define MAX_TEST	8				// Last test # to run (7 now)

#define MAX_OPS		4				// OperationQueue max, Apple suggests this be close to the number of cores but less than 64 for sure (4)
#define NUM_OPS		(5*MAX_OPS)		// Ops per test

#define iCount		100				// loops per test - (100)

#if 0	// 0 == no debug, 1 == lots of mesages
#define TLOG(...) NSLog(__VA_ARGS__)
#else
#define TLOG(...)
#endif

#define WAIT_UNTIL(x, y, msg)						\
	for(int iii=0; iii < NUM_OPS*10 && !(x); ++iii){\
		if(!iii) {TLOG(@"WAITING " #y "...");}		\
		usleep(10000);								\
	}												\
	if(!(x)) {										\
		NSLog(@"FAILED ON LOOP %d UNTIL" #y , i);	\
		[self dump];								\
		XCTAssertTrue((x), @"%@", (msg));					\
		return;										\
	} else {										\
		TLOG(@"...DONE " #y);						\
	}												\
	while(0)

#define WAIT_WHILE(x, y, msg)						\
	for(int iii=0; iii < NUM_OPS*10 && (x); ++iii) {\
		if(!iii) {TLOG(@"WAITING " #y "...");}		\
		usleep(10000);								\
	}												\
	if((x)) {										\
		NSLog(@"FAILED ON LOOP %d WHILE " #y , i);	\
		[self dump];								\
		XCTAssertFalse((x), @"%@", (msg));					\
		return;										\
	} else {										\
		TLOG(@"...DONE " #y);						\
	}												\
	while(0)

//static void myAlrm(int sig)
//{
	//NSLog(@"ALARM!!!!");
//}

// //typedef enum {nofailure, failAtSetup, failAtStartup, failAfterFirstMsg, failWithFailureMsg } forceFailure;

@interface FECWF_Tests () <FECWF_OPSRUNNER_PROTOCOL, TestOperationProtocol>

@end

//typedef enum { forcingOff=0, failAtSetup, failAtStartup, forceSuccess, forceFailure, forceRetry } forceMode;

@implementation FECWF_Tests
{
	__block int				opFailed, opSucceeded, opNeverRan;
	int32_t					stageCounters[atEnd];

	FECWF_OPERATIONSRUNNER *operationsRunner;
	int						count;
	dispatch_queue_t		queue;
	dispatch_group_t		group;
}

- (void)dealloc
{
	[operationsRunner cancelOperations];	// you can send this at any time, for instance when the 'Back' button is tapped
}

- (void)setUp
{
    [super setUp];

	ORSessionDelegate *del = [ORSessionDelegate new];
	
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.URLCache = nil;
assert(config.HTTPShouldSetCookies);
	config.HTTPShouldSetCookies = YES;
	config.HTTPShouldUsePipelining = YES;
	
	[FECWF_OPERATIONSRUNNER createSharedSessionWithConfiguration:config delegate:del];

	operationsRunner = [[FECWF_OPERATIONSRUNNER alloc] initWithDelegate:self];

	if(!operationsRunner.delegateQueue) {
		// re-using it should be more stressful than getting a new one each time
		queue = dispatch_queue_create("com.fecw.test", DISPATCH_QUEUE_SERIAL);
		group = dispatch_group_create();
	
		operationsRunner.delegateQueue = queue;
		operationsRunner.delegateGroup = group;
		operationsRunner.maxOps = MAX_OPS;
		assert(operationsRunner.msgDelOn == msgOnSpecificQueue);
		
		// Having ops run slowly is more likely to cause logic errors to show up in testing
		operationsRunner.priority = QOS_CLASS_BACKGROUND; // QOS_CLASS_BACKGROUND;
		dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
	}
	count = NUM_OPS;
}

- (void)tearDown
{
    // Tear-down code here.
	[operationsRunner cancelOperations];
	dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [super tearDown];
}

- (void)runOperationsWithForceAction:(forceMode)action delay:(double)msDelay type:(BOOL)allAtOnce
{
	static int i;
	
	// need autorelease since "set" is in the main thread's autorelease pool, takes a while for system to release it (which is ultimately does, but not in time for the dealloc test)
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);

	@autoreleasepool {
		NSMutableOrderedSet *set;
		if(allAtOnce) set = [NSMutableOrderedSet orderedSetWithCapacity:count];
		
		for(int j=0; j<count; ++j) {
			TestOperation *t = [TestOperation new];
			t.delegate = self;
			t.forceAction = action;
			t.delayInMain = msDelay;
			{
				NSString *msg = [NSString stringWithFormat:@"Op %d", j];
				if(allAtOnce) {
					t.runMessage = msg;
					[set addObject:t];
				} else {
					dispatch_async([self queueToUse:i+j], ^
						{
							[operationsRunner runOperation:t withMsg:msg];
							dispatch_semaphore_signal(sema);
						} );
				}
			}
		}

		if(allAtOnce) {
			dispatch_async([self queueToUse:i], ^
				{
					[operationsRunner runOperations:set];
					dispatch_semaphore_signal(sema);
				} );
		}
	}
	
	for(int k=0; k<(allAtOnce?1:count); ++k) {
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	}

	++i;
}

- (void)dump
{
	int i=0;
	NSLog(@"OperationsCount        = %d", (int)[operationsRunner operationsCount]);
	NSLog(@"opFailed               = %d", opFailed);
	NSLog(@"opSucceeded            = %d", opSucceeded);
	NSLog(@"opNeverRan             = %d", opNeverRan);
	NSLog(@"stageCounters[setup]   = %d", stageCounters[i++]);
	NSLog(@"stageCounters[started] = %d", stageCounters[i++]);
	NSLog(@"stageCounters[finish]  = %d", stageCounters[i++]);
	NSLog(@"stageCounters[exit]    = %d", stageCounters[i++]);
}

#if 0 >= MIN_TEST && 0 <= MAX_TEST

- (void)test0
// Verify ops complete when forced to succeed
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];
		[self runOperationsWithForceAction:forceSuccess delay:0 type:(i&1) ? YES : NO];

		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");

		WAIT_UNTIL(count == (opFailed+opSucceeded+opNeverRan), 2, @"All ops did not complete");
		XCTAssertEqual(opSucceeded, count, @"All ops should have succeeded");
	}
}
#endif

#if 1 >= MIN_TEST && 1 <= MAX_TEST

- (void)test1
// Verify ops complete when forced to fail
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];

		[self runOperationsWithForceAction:forceFailure delay:0 type:(i&1) ? YES : NO];

		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");

		WAIT_UNTIL(count == (opFailed+opSucceeded+opNeverRan), 2, @"All ops did not complete");
		if(opFailed != count) [self dump];
		XCTAssertEqual(opFailed, count, @"All ops should have failed");

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

		[self runOperationsWithForceAction:forcingOff delay:0 type:(i&1) ? YES : NO];
		
		[operationsRunner cancelOperations];

//sleep(1);
		
		if([operationsRunner operationsCount]) {
			NSLog(@"OPERATIONS: %@", [operationsRunner description]);
		}
		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");

		XCTAssertTrue([self adjustOperationsCount:0 atStage:atSetup] <= count, @"Should only have a few");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atStart] <= count, @"Should only have a few");
		XCTAssertEqual(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
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
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];

		[self runOperationsWithForceAction:forcingOff delay:TIMER_DELAY * 10 * 1000000.0 type:(i&1) ? YES : NO];
		BOOL ret = [operationsRunner cancelOperations];
		XCTAssertTrue(ret, @"Cancel failed");
		
		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");

		XCTAssertTrue([self adjustOperationsCount:0 atStage:atFinish] == 0, @"Should never reach finish");
		XCTAssertEqual(opFailed+opSucceeded+opNeverRan, 0, @"Nothing should completed or failed");
		//[self dump];
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

		[self runOperationsWithForceAction:failAtSetup delay:0 type:(i&1) ? YES : NO];

		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");
	
		WAIT_UNTIL(opNeverRan == count, 1, @"Some operation did not complete");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atStart] == 0, @"Should never reach start");
		XCTAssertEqual(opNeverRan, count, @"Nothing should completed or failed");
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

		[self runOperationsWithForceAction:failAtStartup delay:0 type:(i&1) ? YES : NO];

		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");

		XCTAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"Should never reach start");
		XCTAssertEqual(opNeverRan, count, @"Nothing should completed or failed");
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

		[self runOperationsWithForceAction:forceFailure delay:0 type:(i&1) ? YES : NO];

		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");

		XCTAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"All should reach start");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atFinish] == count, @"All should reach start");
		XCTAssertEqual(opFailed, count, @"All failed");
	}
}
#endif

#if 7 >= MIN_TEST && 7 <= MAX_TEST
- (void)test7
{
	for(int i=1; i<=iCount; ++i) {
		TLOG(@"TEST %d: ==================================================================================", i);
		[self loopInit];

		[self runOperationsWithForceAction:forceSuccess delay:0 type:(i&1) ? YES : NO];
		
		WAIT_UNTIL(operationsRunner.operationsCount == 0, 1, @"Some operation did not cancel");
		long ret = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
		XCTAssertFalse((BOOL)ret, @"All should complete");

		XCTAssertTrue([self adjustOperationsCount:0 atStage:atSetup] == count, @"All should reach setup");
		XCTAssertTrue([self adjustOperationsCount:0 atStage:atStart] == count, @"All should reach start");
		XCTAssertEqual(opSucceeded, count, @"All success");
	}
}
#endif

- (dispatch_queue_t)queueToUse:(int)i
{
	long priority;
	switch(i % 4) {
	case 0:	priority = QOS_CLASS_USER_INITIATED; break;
	case 1:	priority = QOS_CLASS_DEFAULT; break;
	case 2:	priority = QOS_CLASS_UTILITY; break;
	case 3:	default: priority = QOS_CLASS_BACKGROUND;	break;
	}
	return dispatch_get_global_queue(priority, 0);
}

#if 0
- (BOOL)waitTilRunning
{
	__block int cnt = 0;
	for(int i=0; i<10; ++i) {
		cnt = 0;
		[operationsRunner enumerateOperations:^(FECWF_CONCURRENT_OPERATION *op)
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

	//XCTAssertEqual(opFailed+opSucceeded, 0, @"Nothing should completed or failed");
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

	[operationsRunner restartOperations];
}

- (void)register:(id)op atStage:(registrationStage)stage
{
	//NSLog(@"register %d", stage);
	[self adjustOperationsCount:1 atStage:stage];
}

// since we queue operations on threads, there may be multiple cases of "remainingOps == 0", won't happen on main thread
- (void)operationFinished:(FECWF_WEBFETCHER *)op count:(NSUInteger)remainingOps	// on queue
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

@end


