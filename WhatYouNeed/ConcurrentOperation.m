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

#import "ConcurrentOperation.h"

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

@interface ConcurrentOperation (DoesNotExist)

- (void)timer:(NSTimer *)t; // keep the compiler happy with an unfullfilled promise

@end

@interface ConcurrentOperation ()
@property(atomic, weak, readwrite) NSThread *thread;
@property(atomic, assign, readwrite) BOOL isCancelled;
@property(atomic, assign, readwrite) BOOL isExecuting;
@property(atomic, assign, readwrite) BOOL isFinished;
@property(atomic, strong, readwrite) NSTimer *co_timer;
#if defined(UNIT_TESTING)
@property(atomic, strong, readwrite) concurrentBlock block;
#endif

@end

@implementation ConcurrentOperation
{
	   dispatch_semaphore_t semaphore;
}

- (instancetype)init
{
	if((self = [super init])) {
		semaphore = dispatch_semaphore_create(1);
	}
	return self;
}

- (void)main
{
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	if(!self.isCancelled) {
		id obj;
		if((obj = [self setup]) && [self start:obj]) {
			// makes runloop functional
			self.thread	= [NSThread currentThread];
#ifndef NDEBUG
			self.thread.name = _runMessage;
#endif
			self.isExecuting = YES;
			self.co_timer = [NSTimer scheduledTimerWithTimeInterval:60*60 target:self selector:@selector(timer:) userInfo:nil repeats:NO];

			//NSLog(@"%@ enter loop: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			BOOL ret = YES;
			while(ret && !self.isFinished) {
				dispatch_semaphore_signal(semaphore);
				ret = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
				dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
				LOG(@"%@ RUN_LOOP: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			}
#if defined(UNIT_TESTING)
			if(self.block) {
				self.block(self);
			}
#endif
			[self cancelTimer];
			self.isExecuting = NO;
			self.thread = nil;

		}
		if(self.isCancelled) {
			[self cancel];
		}
	}
	dispatch_semaphore_signal(semaphore);	// so cancel and/or final block don't take a long time
}

- (void)cancelTimer
{
	[self.co_timer invalidate], self.co_timer = nil;
}

- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay
{
	BOOL ret = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, millisecondDelay*NSEC_PER_MSEC)) ? NO : YES;
	if(ret) {
		self.isCancelled = YES;
		if(self.isExecuting && !self.isFinished) {
			[self performSelector:@selector(cancel) onThread:self.thread withObject:nil waitUntilDone:NO];
			ret = YES;
		}
		dispatch_semaphore_signal(semaphore);
	} else {
		LOG(@"%@ failed to get the locking semaphore", self);
	}
	return ret;
}

- (void)cancel
{
	LOG(@"%@: got CANCEL", self);
	[self cancelTimer];
	
	self.isFinished = YES;
}

- (id)setup	// on thread
{
	return @"";
}

- (BOOL)start:(id)setupObject	// on thread
{
	LOG(@"%@ start: isExecuting=%d", self.runMessage, self.isExecuting);
	return YES;
}

- (void)completed				// on thread, subclasses to override then finally call super
{
	[self finish];
}

- (void)failed					// on thread, subclasses to override then finally call super
{
	[self finish];
}

- (void)finish
{
	[self cancelTimer];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"ConcurrentOp[\"%@\"]", _runMessage];
}

- (void)dealloc
{
	LOG(@"%@ Dealloc: isExecuting=%d isFinished=%d isCancelled=%d", _runMessage, _isExecuting, _isFinished, _isCancelled);
#ifdef VERIFY_DEALLOC
	if(_finishBlock) {
		_finishBlock();
	}
#endif
}

@end
