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

#ifdef VERIFY_DEALLOC
#include <libkern/OSAtomic.h>
#endif

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

#import "OperationsRunner.h"

#import "ConcurrentOperation.h"

@interface FECWF_CONCURRENT_OPERATION (OperationsRunner)
- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay;							// for use by OperationsRunner
@end

@interface FECWF_OPERATIONSRUNNER ()
@property (nonatomic, strong) NSMutableSet				*operations;
@property (nonatomic, strong) NSMutableOrderedSet		*operationsOnHold;	// output ops in the order they arrived
@property (nonatomic, assign) dispatch_semaphore_t		dataSema;
@property (nonatomic, assign) dispatch_queue_t			opRunnerQueue;
@property (nonatomic, assign) dispatch_queue_t			operationsQueue;
@property (nonatomic, assign) dispatch_group_t			opRunnerGroup;
@property (nonatomic, assign) dispatch_group_t			operationsGroup;
@property (atomic, weak) id <FECWF_OPSRUNNER_PROTOCOL>	delegate;
@property (atomic, weak) id <FECWF_OPSRUNNER_PROTOCOL>	savedDelegate;
@property (atomic, assign) BOOL							cancelled;
#ifdef VERIFY_DEALLOC
@property (nonatomic, assign) dispatch_semaphore_t		deallocs;
#endif

@end

@implementation FECWF_OPERATIONSRUNNER
{
	long		_priority;							// the queue priority      
#ifdef VERIFY_DEALLOC
	int32_t		_DO_NOT_ACCESS_operationsTotal;		// named so as to discourage direct access
#endif
}
@dynamic priority;

// so forwardingTargetForSelector has something to send to if no operationRunner exists
+ (BOOL)cancelOperations { return NO; }
+ (BOOL)restartOperations { return NO; }
+ (BOOL)disposeOperations { return NO; }

- (id)initWithDelegate:(id <FECWF_OPSRUNNER_PROTOCOL>)del
{
    if((self = [super init])) {
		_savedDelegate = _delegate = del;
		
		_operations			= [NSMutableSet setWithCapacity:10];
		_operationsOnHold	= [NSMutableOrderedSet orderedSetWithCapacity:10];
		_dataSema			= dispatch_semaphore_create(1);
#ifdef VERIFY_DEALLOC
		_deallocs			= dispatch_semaphore_create(0);
#endif
		_opRunnerQueue		= dispatch_queue_create("com.dfh.opRunnerQueue", DISPATCH_QUEUE_SERIAL);
		_opRunnerGroup		= dispatch_group_create();
		_operationsQueue	= dispatch_queue_create("com.dfh.operationsQueue", DISPATCH_QUEUE_CONCURRENT);
		_operationsGroup	= dispatch_group_create();
		
		_priority			= DEFAULT_PRIORITY;
		_maxOps				= DEFAULT_MAX_OPS;
		_mSecCancelDelay	= DEFAULT_MILLI_SEC_CANCEL_DELAY;

#ifdef VERIFY_DEALLOC
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
#ifdef VERIFY_DEALLOC
	dispatch_release(_deallocs);
#endif
}

- (FECWF_OPERATIONSRUNNER *)operationsRunner
{
	return self;
}

#ifdef VERIFY_DEALLOC
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
	
		// keep this around while in development
		switch(priority) {
		case DISPATCH_QUEUE_PRIORITY_HIGH:
		case DISPATCH_QUEUE_PRIORITY_DEFAULT:
		case DISPATCH_QUEUE_PRIORITY_LOW:
		case DISPATCH_QUEUE_PRIORITY_BACKGROUND:
			break;
		default:
			assert(!"Invalid Priority Value");
			return;
		}
		_priority = priority;
		
		dispatch_queue_t target = dispatch_get_global_queue(priority, 0);
		dispatch_set_target_queue(_opRunnerQueue, target);
		dispatch_set_target_queue(_operationsQueue, target);
	}
}

- (void)runOperation:(FECWF_CONCURRENT_OPERATION *)op withMsg:(NSString *)msg
{
	if(self.cancelled) {
		return;
	}
	
#ifdef VERIFY_DEALLOC
	{
		[self adjustOperationsTotal:1];	// peg immediately
		__weak __typeof__(self) weakSelf = self;
		op.deallocBlock =   ^{
								__typeof__(self) strongSelf = weakSelf;
								if(strongSelf) {
									dispatch_semaphore_signal(strongSelf.deallocs);
								}
							};
	}
#endif

#ifndef NDEBUG
	((FECWF_CONCURRENT_OPERATION *)op).runMessage = msg;
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

- (BOOL)runOperations:(NSOrderedSet *)ops
{
	int32_t count = (int32_t)[ops count];
	if(!count) {
		return NO;
	}
	if(self.cancelled) {
		return NO;
	}

#ifdef VERIFY_DEALLOC
	{
		[self adjustOperationsTotal:count];	// peg immediately
		__weak __typeof__(self) weakSelf = self;
		[ops enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, NSUInteger idx, BOOL *stop)
			{
				op.deallocBlock = ^	{
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
			[rSet enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, BOOL *stop)
				{
					[weakSelf _runOperation:op];
				} ];
				
		} );
	return YES;
}

- (BOOL)addOp:(FECWF_CONCURRENT_OPERATION *)op
{
	BOOL ret;

/***/dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);
	if([_operations count] >= self.maxOps) {
		[_operationsOnHold addObject:op];
		ret = FALSE;
	} else {
		[_operations addObject:op];	// Second we retain and save a reference to the operation
		ret = YES;
	}	
/***/dispatch_semaphore_signal(_dataSema);
	
	return ret;
}
- (NSSet *)addOps:(NSOrderedSet *)ops
{
	NSMutableSet *rSet = [NSMutableSet setWithCapacity:[ops count]];

/***/dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);
	[ops enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, NSUInteger idx, BOOL *stop)
		{
			if([_operations count] >= self.maxOps) {
				[_operationsOnHold addObject:op];
			} else {
				[_operations addObject:op];	// Second we retain and save a reference to the operation
				[rSet addObject:op];
			}
		} ];
/***/dispatch_semaphore_signal(_dataSema);

	return rSet;
}
- (NSUInteger)cancelAllOps
{
	__block NSUInteger cancelFailures = 0;
	
/***/dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);
#if 0
	[_operationsOnHold enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, NSUInteger idx, BOOL *stop)
		{
			[op _OR_cancel:_mSecCancelDelay];
		} ];
#endif
	[_operationsOnHold removeAllObjects];

	[_operations enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, BOOL *stop)
		{
			BOOL ret = [op _OR_cancel:_mSecCancelDelay];
			if(!ret) ++cancelFailures;
			//NSLog(@"SEND CANCEL TO %@", op.runMessage);
		} ];
	[_operations removeAllObjects];
/***/dispatch_semaphore_signal(_dataSema);
	
	return cancelFailures;
}
- (NSUInteger)operationsCount
{
/***/dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);
	NSUInteger count = [_operations count] + [_operationsOnHold count];
/***/dispatch_semaphore_signal(_dataSema);
	
	return count;
}

- (void)_runOperation:(FECWF_CONCURRENT_OPERATION *)op	// on queue
{
	if(self.cancelled) {
		//LOG(@"Cancel Before Running: %@", op);
		[self _operationFinished:op];
		return;
	}

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
				//NSLog(@"LEAVE MAIN %@", op.runMessage);
			}

			// Completion block
			if(strongSelf && !op.isCancelled) {
				__weak __typeof__(op) weakOp = op;
				dispatch_group_async(strongSelf.opRunnerGroup, strongSelf.opRunnerQueue, ^
					{
						__typeof__(op) strongOp = weakOp;
						if(strongOp)
						{
//NSLog(@"SEND FINISH %@", op.runMessage);
							[strongSelf _operationFinished:op];
						}
					} );
			}
		} );
}

- (BOOL)cancelOperations
{
	if(self.cancelled == YES) {
		return YES;
	}
	
	LOG(@"OR cancelOperations");
	
	self.delegate = nil;
	self.cancelled = YES;

	LOG(@"CANCEL ALL OPS");

	NSUInteger cancelFailures = [self cancelAllOps];
	assert(!cancelFailures);
	
	LOG(@"WAIT FOR OPS GROUP TO COMPLETE");
	long ret = dispatch_group_wait(_operationsGroup, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
	if(ret) dispatch_debug(_operationsGroup, "Howdie");
	assert(!ret && "Run Ops");

	ret += dispatch_group_wait(_opRunnerGroup, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));
	assert(!ret && "Wait for operations release");

#ifdef VERIFY_DEALLOC
	[self testIfAllDealloced];
#endif

	return (ret || cancelFailures) ? NO : YES;
}

- (BOOL)restartOperations
{
	self.delegate = self.savedDelegate;
	self.cancelled = NO;
	return YES;
}

- (BOOL)disposeOperations
{
	return YES;
}

#ifdef VERIFY_DEALLOC
- (void)testIfAllDealloced
{
	// local counter for this test
	int32_t count = [self adjustOperationsTotal:0];
	[self adjustOperationsTotal:-count];

	BOOL completed = YES;
	for(int32_t i=1; i<=count; ++i) {
		long ret = dispatch_semaphore_wait(_deallocs, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC));	// 1 second
		if(ret) {
			NSLog(@"+++++++++++++++++++WARNING[%d]: %d OPERATIONS DID NOT DEALLOC", count, count-i+1);		// always print this!
			completed = NO;
			break;
		}
	}
}
#endif

- (void)_operationFinished:(FECWF_CONCURRENT_OPERATION *)op	// excutes in opRunnerQueue
{
	if(self.cancelled) {
		return;
	}
	assert(!op.isCancelled);
	
	//NSLog(@"_operationFinished op=%@", op.runMessage);
	//LOG(@"OP RUNNER GOT A MESSAGE %d for thread %@", _msgDelOn, delegateThread);	

	switch(_msgDelOn) {
	case msgDelOnMainThread:
		[self performSelectorOnMainThread:@selector(operationFinished:) withObject:op waitUntilDone:NO];
		break;

	case msgDelOnAnyThread:
		[self operationFinished:op];
		break;
	
	case msgOnSpecificThread:
		[self performSelector:@selector(operationFinished:) onThread:_delegateThread withObject:op waitUntilDone:NO];
		break;
		
	case msgOnSpecificQueue:
	{
		dispatch_block_t b =   ^{
									[self operationFinished:op];
								};
		if(_delegateGroup) {
			dispatch_group_async(_delegateGroup, _delegateQueue, b);
		} else {
			dispatch_async(_delegateQueue, b);
		}
	}	break;
	}
}

- (void)operationFinished:(FECWF_CONCURRENT_OPERATION *)op // excutes from multiple possible threads
{
	// Could have been queued on a thread and gotten cancelled. Once past this test the operation will be delivered
	if(op.isCancelled || self.cancelled) {
		return;
	}

/***/dispatch_semaphore_wait(_dataSema, DISPATCH_TIME_FOREVER);
	[_operations removeObject:op];
	NSUInteger remainingCount = [_operationsOnHold count];
	FECWF_CONCURRENT_OPERATION *runOp;
	if(remainingCount) {
		runOp = [_operationsOnHold objectAtIndex:0];
		[_operationsOnHold removeObjectAtIndex:0];
		[_operations addObject:runOp];
		remainingCount -= 1;
	}
	remainingCount += [_operations count];
/***/dispatch_semaphore_signal(_dataSema);

	if(runOp) {
		__weak __typeof__(self) weakSelf = self;
		dispatch_group_async(_opRunnerGroup, _opRunnerQueue, ^
			{
				[weakSelf _runOperation:runOp];
			} );
	}
	
	[self.delegate operationFinished:op count:remainingCount];

#if defined(VERIFY_DEALLOC) && !defined(UNIT_TESTING)
	if(!remainingCount) {
		NSLog(@"DEALLOC TEST");
		[self testIfAllDealloced];
	}
#endif
}

- (NSString *)description
{
	NSMutableString *mStr = [NSMutableString stringWithCapacity:256];
	[mStr appendFormat:@"OpsOnHold=%d OpsRunning=%d\n", [_operationsOnHold count], [_operations count]];
	[_operations enumerateObjectsUsingBlock:^(FECWF_CONCURRENT_OPERATION *op, BOOL *stop)
		{
			[mStr appendString:[op description]];
			[mStr appendString:@"\n"];
		}];
	return mStr;
}

@end
