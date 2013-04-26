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
- (void)_OR_cancel;										// for use by OperationsRunner
- (void)performBlock:(concurrentBlock)b;
@end

@interface OperationsRunner ()
@property (nonatomic, strong) NSMutableSet				*operations;
@property (nonatomic, strong) NSMutableOrderedSet		*operationsOnHold;	// output ops in the order they arrived
@property (nonatomic, assign) dispatch_queue_t			opRunnerQueue;
@property (nonatomic, assign) dispatch_queue_t			operationsQueue;
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

}
@dynamic priority;

- (id)initWithDelegate:(id <OperationsRunnerProtocol>)del
{
    if((self = [super init])) {
		_savedDelegate = _delegate = del;
		
		_operations			= [NSMutableSet setWithCapacity:10];
		_operationsOnHold	= [NSMutableOrderedSet orderedSetWithCapacity:10];
		_opRunnerQueue		= dispatch_queue_create("com.dfh.opRunnerQueue", DISPATCH_QUEUE_SERIAL);
		_operationsQueue	= dispatch_queue_create("com.dfh.operationsQueue", DISPATCH_QUEUE_CONCURRENT);
		_operationsGroup	= dispatch_group_create();
		
		_priority			= DISPATCH_QUEUE_PRIORITY_DEFAULT;
		_maxOps				= 1000000;	// some absurdly large number

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
	dispatch_release(_operationsQueue);
	dispatch_release(_operationsGroup);
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

- (void)runOperation:(ConcurrentOperation *)op withMsg:(NSString *)msg
{
#ifndef NDEBUG
	if(self.cancelled) {
		assert([self adjustOperationsCount:0] == 0);
	}
#endif
	self.cancelled = NO;
	
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
	__weak __typeof__(self) weakSelf = self;
	dispatch_group_async(_operationsGroup, _opRunnerQueue, ^
		{
			[weakSelf _runOperation:op];
		} );
}

- (BOOL)runOperations:(NSSet *)ops
{
	int32_t count = (int32_t)[ops count];
	if(!count) {
		return NO;
	}

#ifndef NDEBUG
	if(self.cancelled) {
		assert([self adjustOperationsCount:0] == 0);
	}
#endif
	self.cancelled = NO;
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
	
	// Programming With ARC Release Notes pg 10 - non-trivial weak cases
	__weak __typeof__(self) weakSelf = self;
	dispatch_group_async(_operationsGroup, _opRunnerQueue, ^
		{
			[ops enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
				{
					[weakSelf _runOperation:op];
				} ];
				
		} );
	return YES;
}

- (void)_runOperation:(ConcurrentOperation *)op	// on queue
{
	if(self.cancelled) {
		LOG(@"Cancel Before Running: %@", op);
		return;
	}
	
	if([_operations count] >= self.maxOps) {
		LOG(@"Hold %@", op);
		[self.operationsOnHold addObject:op];
		return;
	}

#ifndef NDEBUG
	if(!self.noDebugMsgs) LOG(@"Run Operation: %@", op.runMessage);
#endif
	self.delegate = self.savedDelegate;

	[_operations addObject:op];	// Second we retain and save a reference to the operation

	__weak __typeof__(self) weakSelf = self;
	dispatch_group_async(_operationsGroup, _operationsQueue, ^
		{
			__typeof__(self) strongSelf = weakSelf;

			// Run the operation
			[op main];

			// Completion block
			if(strongSelf) { //  && !strongSelf.cancelled
				__weak __typeof__(op) weakOp = op;
				dispatch_group_async(strongSelf.operationsGroup, strongSelf.opRunnerQueue, ^
					{
						__typeof__(op) strongOp = weakOp;
						if(strongOp) {
							[strongSelf _operationFinished:strongOp];
						}
					} );
			}
		} );
}

- (void)cancelOperations
{
	if(self.cancelled == YES) {
		return;
	}
	
	LOG(@"OR cancelOperations");
	
	self.delegate = nil;
	self.cancelled = YES;

	// Cancel all active apps
	[self enumerateOperations:^(ConcurrentOperation *op)
		{
			[op _OR_cancel];
			LOG(@"SEND CANCEL TO %@", op.runMessage);
		}];
	
	// insure that the all operations and dispatches they make have cleared out
	dispatch_group_wait(_operationsGroup, DISPATCH_TIME_FOREVER);

	// now that all ops have completed, we can wipe the array out
	dispatch_group_async(_operationsGroup, _opRunnerQueue, ^	// has to be SYNC or you get crashes
		{
			[_operations removeAllObjects];
			[_operationsOnHold removeAllObjects];
		} );
	// wait for the removeAllObjects
	dispatch_group_wait(_operationsGroup, DISPATCH_TIME_FOREVER);
	assert(![_operations count]);

#if VERIFY_DEALLOC == 1
	[self testIfAllDealloced];
#endif

	int32_t curval = [self adjustOperationsCount:0];
	[self adjustOperationsCount:-curval];
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
}
#endif

- (void)enumerateOperations:(concurrentBlock)b
{
	//LOG(@"OP enumerateOperations");
	dispatch_group_async(_operationsGroup, _opRunnerQueue, ^
		{
			[_operations enumerateObjectsUsingBlock:^(ConcurrentOperation *op, BOOL *stop)
				{
					[op performBlock:b];
					//b(op);
				}];   
		} );
}

- (NSUInteger)operationsCount
{
	return [self adjustOperationsCount:0];
}

- (void)_operationFinished:(ConcurrentOperation *)op	// excutes in opRunnerQueue
{
	[_operations removeObject:op];
	int32_t nVal = [self adjustOperationsCount:-1];
	assert(nVal >= 0);
	assert(!(nVal == 0 && [_operations count]));	// if count == 0 better not have any operations in the XXXX
	// assert(!([_operations count] == 0 && nVal));	Since we bump the counter at the submisson point, not in XXXX, this could actually occurr

	// if you cancel the operation when its in the set, will hit this case
	if(op.isCancelled || self.cancelled) {
		LOG(@"one of op.isCancelled=%d or self.isCancelled=%d", op.isCancelled, self.cancelled);
		return;
	}

	if([_operationsOnHold count] && [_operations count] < _maxOps) {
		ConcurrentOperation *nOp = [_operationsOnHold objectAtIndex:0];
		[_operationsOnHold removeObjectAtIndex:0];
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
