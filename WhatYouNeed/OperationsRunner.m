//
// FastEasyConcurrentWebFetches (TM)
// Copyright (C) 2012-2013 by David Hoerl
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#include <libkern/OSAtomic.h>

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

#import "OperationsRunner.h"

#import "ConcurrentOperation.h"

@interface ConcurrentOperation (OperationsRunner)
- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay;							// for use by OperationsRunner
@end

@interface OperationsRunner ()
@property (nonatomic, strong) NSMutableSet				*operations;
@property (nonatomic, strong) NSMutableOrderedSet		*operationsOnHold;	// output ops in the order they arrived
@property (nonatomic, assign) dispatch_semaphore_t		dataSema;
@property (nonatomic, assign) dispatch_queue_t			opRunnerQueue;
@property (nonatomic, assign) dispatch_queue_t			operationsQueue;
@property (nonatomic, assign) dispatch_group_t			opRunnerGroup;
@property (nonatomic, assign) dispatch_group_t			operationsGroup;
@property (atomic, weak) id <OperationsRunnerProtocol>	delegate;
@property (atomic, weak) id <OperationsRunnerProtocol>	savedDelegate;
@property (atomic, assign) BOOL							cancelled;
#if VERIFY_DEALLOC == 1
@property (nonatomic, assign) dispatch_semaphore_t		deallocs;
#endif

@end

@implementation OperationsRunner
{
	long		_priority;							// the queue priority
	int32_t		_DO_NOT_ACCESS_operationsCount;		// named so as to discourage direct access

#if VERIFY_DEALLOC == 1
	int32_t		_DO_NOT_ACCESS_operationsTotal;		// named so as to discourage direct access
#endif
int cnt;
}
@dynamic priority;

- (id)initWithDelegate:(id <OperationsRunnerProtocol>)del
{
    if((self = [super init])) {
		_savedDelegate = _delegate = del;
		
		_operations			= [NSMutableSet setWithCapacity:10];
		_operationsOnHold	= [NSMutableOrderedSet orderedSetWithCapacity:10];
		_dataSema			= dispatch_semaphore_create(1);
		_deallocs			= dispatch_semaphore_create(0);
		
		_opRunnerQueue		= dispatch_queue_create("com.dfh.opRunnerQueue", DISPATCH_QUEUE_SERIAL);
		_opRunnerGroup		= dispatch_group_create();
		_operationsQueue	= dispatch_queue_create("com.dfh.operationsQueue", DISPATCH_QUEUE_CONCURRENT);
		_operationsGroup	= dispatch_group_create();
		
		_priority			= DEFAULT_PRIORITY;
		_maxOps				= DEFAULT_MAX_OPS;
		_mSecCancelDelay	= DEFAULT_MILLI_SEC_CANCEL_DELAY;

#if VERIFY_DEALLOC == 1
		_deallocs			= dispatch_semaphore_create(0);
#endif
	}
	return self;
}
- (void)dealloc
{
	[self cancelOperations];

	dispatch_release(_opRunnerQueue);
	dispatch_release(_opRunnerGroup);
	dispatch_release(_operationsQueue);
	dispatch_release(_operationsGroup);
	dispatch_release(_dataSema);
#if VERIFY_DEALLOC == 1
	dispatch_release(_deallocs);
#endif
}

- (int32_t)adjustOperationsCount:(int32_t)val
{
	int32_t nVal = OSAtomicAdd32(val, &_DO_NOT_ACCESS_operationsCount);
	return nVal;
}

#if VERIFY_DEALLOC == 1
- (int32_t)adjustOperationsTotal:(int32_t)val
{
	int32_t nVal = OSAtomicAdd32(val, &_DO_NOT_ACCESS_operationsTotal);
	return nVal;
}
#endif

- (void)setDelegateThread:(NSThread *)delegateThread
{
	if(delegateThread != _delegateThread) {
		_delegateThread = delegateThread;
		_msgDelOn = msgOnSpecificThread;
	}
}

- (void)setDelegateQueue:(dispatch_queue_t)delegateQueue
{
	if(delegateQueue != _delegateQueue) {
		_delegateQueue = delegateQueue;
		_msgDelOn = msgOnSpecificQueue;
	}
}

- (void)setPriority:(long)priority
{	
	if(_priority != priority) {
		long cmdPriority;
		long opsPriority;
		// keep this around while in development
		switch(priority) {
		case DISPATCH_QUEUE_PRIORITY_HIGH:
			cmdPriority = DISPATCH_QUEUE_PRIORITY_HIGH;
			opsPriority = DISPATCH_QUEUE_PRIORITY_DEFAULT;
			break;
		case DISPATCH_QUEUE_PRIORITY_DEFAULT:
			cmdPriority = DISPATCH_QUEUE_PRIORITY_DEFAULT;
			opsPriority = DISPATCH_QUEUE_PRIORITY_LOW;
			break;
		case DISPATCH_QUEUE_PRIORITY_LOW:
		case DISPATCH_QUEUE_PRIORITY_BACKGROUND:
			cmdPriority = DISPATCH_QUEUE_PRIORITY_LOW;
			opsPriority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
			break;
		default:
			assert(!"Invalid Priority Value");
			return;
		}
		_priority = priority;
		
		dispatch_set_target_queue(_opRunnerQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_set_target_queue(_operationsQueue, dispatch_get_global_queue(opsPriority, 0));
	}
}

- (void)runOperation:(ConcurrentOperation *)op withMsg:(NSString *)msg
{
	if(self.cancelled) {
		return;
	}
	
	[self adjustOperationsCount:1];	// peg immediately
#if VERIFY_DEALLOC == 1
	{
		[self adjustOperationsTotal:1];	// peg immediately
		__weak __typeof__(self) weakSelf = self;
		op.finishBlock =   ^{
								__typeof__(self) strongSelf = weakSelf;
								if(strongSelf) {
									dispatch_semaphore_signal(strongSelf.deallocs);
								}
							};
	}
#endif

	// Programming With ARC Release Notes pg 10 - non-trivial weak cases

#ifndef NDEBUG
	((ConcurrentOperation *)op).runMessage = msg;
#endif

	if([self addOp:op]) {
		__weak __typeof__(self) weakSelf = self;
		dispatch_group_async(_opRunnerGroup, _opRunnerQueue, ^
			{
				[weakSelf _runOperation:op];
				//NSLog(@"END _run %@", op.runMessage);
			} );
	}
}

- (BOOL)runOperations:(NSSet *)ops
{
	int32_t count = (int32_t)[ops count];
	if(!count) {
		return NO;
	}
	if(self.cancelled) {
		return NO;
	}

	[self adjustOperationsCount:count];	// peg immediately

#if VERIFY_DEALLOC == 1
	{
		[self adjustOperationsTotal:count];	// peg immediately
		__weak __typeof__(self) weakSelf = self;
		[ops enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
			{
				op.finishBlock = ^	{
										__typeof__(self) strongSelf = weakSelf;
										if(strongSelf) {
											dispatch_semaphore_signal(strongSelf.deallocs);
										}
									};
			} ];
			
	}
#endif
	
	NSSet *rSet = [self addOps:ops];

	__weak __typeof__(self) weakSelf = self;
	dispatch_group_async(_opRunnerGroup, _opRunnerQueue, ^
		{
			[rSet enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
				{
					[weakSelf _runOperation:op];
				} ];
				
		} );
	return YES;
}

- (BOOL)addOp:(ConcurrentOperation *)op
{
	BOOL ret;

	dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);

	if([_operations count] >= self.maxOps) {
		//if(cnt>=9900) NSLog(@"Hold %@", op);
		[_operationsOnHold addObject:op];
		ret = FALSE;
	} else {
		[_operations addObject:op];	// Second we retain and save a reference to the operation
		ret = YES;
	}
	
	dispatch_semaphore_signal(_dataSema);

	return ret;
}
- (NSSet *)addOps:(NSSet *)ops
{
	NSMutableSet *rSet = [NSMutableSet setWithCapacity:[ops count]];

	dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);

	[ops enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
		{
			if([_operations count] >= self.maxOps) {
				[_operationsOnHold addObject:op];
			} else {
				[_operations addObject:op];	// Second we retain and save a reference to the operation
				[rSet addObject:op];
			}
		} ];

	dispatch_semaphore_signal(_dataSema);

	return rSet;
}
- (ConcurrentOperation *)removeOp:(ConcurrentOperation *)op
{
	ConcurrentOperation *runOp;

	dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);

	[_operations removeObject:op];
	if([_operationsOnHold count]) {
		runOp = [_operationsOnHold objectAtIndex:0];
		[_operationsOnHold removeObjectAtIndex:0];
	}
	
	dispatch_semaphore_signal(_dataSema);

	return runOp;
}
- (NSUInteger)cancelAllOps
{
	__block NSUInteger cancelFailures = 0;
	
	dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);

	[_operationsOnHold enumerateObjectsUsingBlock:^(ConcurrentOperation *op, NSUInteger idx, BOOL *stop)
		{
			[op _OR_cancel:_mSecCancelDelay];
		} ];
	[_operationsOnHold removeAllObjects];

	[_operations enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
		{
			BOOL ret = [op _OR_cancel:_mSecCancelDelay];
			if(!ret) ++cancelFailures;
			//NSLog(@"SEND CANCEL TO %@", op.runMessage);
		} ];
	[_operations removeAllObjects];
	
	dispatch_semaphore_signal(_dataSema);
	
	return cancelFailures;
}

- (void)_runOperation:(ConcurrentOperation *)op	// on queue
{
	if(self.cancelled) {
		//LOG(@"Cancel Before Running: %@", op);
		return;
	}

//if(cnt>=9900) NSLog(@"RUN %@", op);

#ifndef NDEBUG
	if(!self.noDebugMsgs) LOG(@"Run Operation: %@", op.runMessage);
#endif

	__weak __typeof__(self) weakSelf = self;
	dispatch_group_async(_operationsGroup, _operationsQueue, ^
		{
			__typeof__(self) strongSelf = weakSelf;

			if(!op.isCancelled) {
			// Run the operation
				[op main];
			}

			// Completion block
			if(strongSelf && !op.isCancelled) {
				__weak __typeof__(op) weakOp = op;
				dispatch_group_async(strongSelf.opRunnerGroup, strongSelf.opRunnerQueue, ^
					{
						__typeof__(op) strongOp = weakOp;
						if(strongOp)
						{
							[strongSelf _operationFinished:op];
						}
					} );
			}
		} );
}

- (BOOL)cancelOperations
{
	long ret = 0;

	if(self.cancelled == YES) {
		return YES;
	}
	
	LOG(@"OR cancelOperations");
	
	self.delegate = nil;
	self.cancelled = YES;

	LOG(@"CANCEL ALL OPS");


#if 0
	int32_t totalOps = [self adjustOperationsCount:0];

//	NSLog(@"WAIT FOR RUN GROUP TO COMPLETE");
//	ret = dispatch_group_wait(_opRunnerGroup, dispatch_time(DISPATCH_TIME_NOW, 100*NSEC_PER_SEC));
//ret = 1;
	if(ret)
	{
#if 0
		NSLog(@"_opRunnerGroup: %@", [(__bridge NSObject *)_opRunnerGroup debugDescription]);
		NSLog(@"_opRunnerQueue: %@", [(__bridge NSObject *)_opRunnerQueue debugDescription]);
		NSLog(@"_operationsGroup: %@", [(__bridge NSObject *)_operationsGroup debugDescription]);
		NSLog(@"_operationsQueue: %@", [(__bridge NSObject *)_operationsQueue debugDescription]);
#else
NSLog(@"CNT=%d", cnt);
		dispatch_debug(_opRunnerGroup, "_opRunnerGroup");
		dispatch_debug(_opRunnerQueue, "_opRunnerQueue");
		dispatch_debug(_operationsGroup, "_operationsGroup");
		dispatch_debug(_operationsQueue, "_operationsQueue");
#endif
	}
	assert(!ret && "Run Ops");
	// Cancel all active apps
	
	
	
	__block BOOL cancelFailures = 0;
	dispatch_group_async(_opRunnerGroup, _opRunnerQueue, ^
		{
			[_operationsOnHold enumerateObjectsUsingBlock:^(ConcurrentOperation *op, NSUInteger idx, BOOL *stop)
				{
					[op _OR_cancel:_mSecCancelDelay];
				} ];
			[_operationsOnHold removeAllObjects];

			[_operations enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
				{
					BOOL ret = [op _OR_cancel:_mSecCancelDelay];
					if(!ret) ++cancelFailures;
					//NSLog(@"SEND CANCEL TO %@", op.runMessage);
				} ];
			[_operations removeAllObjects];
		} );

	//NSLog(@"WAIT FOR GROUP TO COMPLETE");
	// wait for the removeAllObjects
#endif

	NSUInteger cancelFailures = [self cancelAllOps];
	
	LOG(@"WAIT FOR OPS GROUP TO COMPLETE");
	ret+= dispatch_group_wait(_operationsGroup, dispatch_time(DISPATCH_TIME_NOW, 100*NSEC_PER_SEC));
	if(ret) dispatch_debug(_operationsGroup, "Howdie");
	assert(!ret && "Run Ops");

//NSLog(@"ONE %d", totalOps);
	ret = dispatch_group_wait(_opRunnerGroup, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
//NSLog(@"TWO");
	assert(!ret && "Wait for operations release");

#if VERIFY_DEALLOC == 1
	LOG(@"WAIT FOR DEALLOC TEST...");
	[self testIfAllDealloced];
	LOG(@"...TEST DONE");
#endif

	int32_t curval = [self adjustOperationsCount:0];
	[self adjustOperationsCount:-curval];
	
	return (ret || cancelFailures) ? NO : YES;
}

- (void)restartOperations
{
	self.delegate = self.savedDelegate;
	self.cancelled = NO;
}

#if VERIFY_DEALLOC == 1
- (void)testIfAllDealloced
{
	// local counter for this test
	int32_t count = [self adjustOperationsTotal:0];
	[self adjustOperationsTotal:-count];

	BOOL completed = YES;
	for(int32_t i=1; i<=count; ++i) {
		long ret = dispatch_semaphore_wait(_deallocs, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));	// 1 second
		if(ret) {
			NSLog(@"+++++++++++++++++++WARNING[%d]: %d OPERATIONS DID NOT DEALLOC", count, count-i+1);
			completed = NO;
			break;
		}
	}
	//if(completed) NSLog(@"ALL OPS DEALLOCED");
}
#endif

#if 0
- (void)enumerateOperations:(concurrentBlock)b
{
	//LOG(@"OP enumerateOperations");
	dispatch_group_async(_operationsGroup, _opRunnerQueue, ^
		{
			[_operations enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
				{
					[op performBlock:b];
				}];   
		} );
}
#endif

- (NSUInteger)operationsCount
{
	return [self adjustOperationsCount:0];
}

- (void)_operationFinished:(ConcurrentOperation *)op	// excutes in opRunnerQueue
{
	ConcurrentOperation *nOp = [self removeOp:op];
	
	int32_t nVal = [self adjustOperationsCount:-1];
	assert(nVal >= 0);
	// assert(!([_operations count] == 0 && nVal));	Since we bump the counter at the submisson point, not in array, this could actually occurr

	// if you cancel the operation when its in the set, will hit this case
	if(op.isCancelled || self.cancelled) {
		LOG(@"one of op.isCancelled=%d or self.isCancelled=%d", op.isCancelled, self.cancelled);
		return;
	}
	if(nOp) {
		[self _runOperation:nOp];
	}

	//LOG(@"OP RUNNER GOT A MESSAGE %d for thread %@", _msgDelOn, delegateThread);	
	NSUInteger count = (NSUInteger)nVal;
	NSDictionary *dict;
	if(_msgDelOn !=  msgOnSpecificQueue) {
		dict = @{ @"op" : op, @"count" : @(count) };
	}

#if VERIFY_DEALLOC == 1
	dispatch_block_t b;
	if(!count) b = ^{
						[self testIfAllDealloced];
					};
#endif

	switch(_msgDelOn) {
	case msgDelOnMainThread:
		[self performSelectorOnMainThread:@selector(operationFinished:) withObject:dict waitUntilDone:NO];
		break;

	case msgDelOnAnyThread:
		[self operationFinished:dict];
		break;
	
	case msgOnSpecificThread:
		[self performSelector:@selector(operationFinished:) onThread:_delegateThread withObject:dict waitUntilDone:NO];
		break;
		
	case msgOnSpecificQueue:
	{
		__weak id <OperationsRunnerProtocol> del = self.delegate;
		dispatch_block_t b =   ^{
									[del operationFinished:op count:count];
								};
		if(_delegateGroup) {
			dispatch_group_async(_delegateGroup, _delegateQueue, b);
		} else {
			dispatch_async(_delegateQueue, b);
		}
	}	break;
	}
}

- (void)operationFinished:(NSDictionary *)dict // excutes from multiple possible threads
{
	ConcurrentOperation *op	= dict[@"op"];
	NSUInteger count		= [(NSNumber *)dict[@"count"] unsignedIntegerValue];
	
	// Could have been queued on a thread and gotten cancelled. Once past this test the operation will be delivered
	if(op.isCancelled || self.cancelled) {
		return;
	}
	
	[self.delegate operationFinished:op count:count];
}

@end
