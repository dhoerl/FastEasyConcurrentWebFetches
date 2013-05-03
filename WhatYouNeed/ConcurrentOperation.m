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

			//LOG(@"%@ enter loop: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			BOOL ret = YES;
			while(ret && !self.isFinished) {
				dispatch_semaphore_signal(semaphore);
				LOG(@"%@ RUN_LOOP: sleep...", self.runMessage);
				ret = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
				dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
				LOG(@"%@ RUN_LOOP: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			}
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
#ifndef NDEBUG
	if(self.co_timer) assert([NSThread currentThread] == self.thread);
#endif
	[self.co_timer invalidate], self.co_timer = nil;
}

- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay
{
	self.isCancelled = YES;

	BOOL ret = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, millisecondDelay*NSEC_PER_MSEC)) ? NO : YES;
	if(ret) {
		if(self.isExecuting && !self.isFinished) {
			LOG(@"%@: send cancel", self.runMessage);
			self.isFinished = YES;	// redundant
			[self performSelector:@selector(cancel) onThread:self.thread withObject:nil waitUntilDone:NO];
			ret = YES;
		}
		dispatch_semaphore_signal(semaphore);
	} else {
		LOG(@"%@ failed to get the locking semaphore in %u milliseconds", self, millisecondDelay);
	}
	return ret;
}

- (void)cancel
{
#ifndef NDEBUG
	if(self.co_timer) assert([NSThread currentThread] == self.thread);
#endif
	LOG(@"%@: got CANCEL", self);
	self.isFinished = YES;
	
	[self cancelTimer];
}

- (id)setup	// on thread
{
	return @"";
}

- (BOOL)start:(id)setupObject	// on thread
{
	LOG(@"%@ Start: isExecuting=%d", self.runMessage, self.isExecuting);
	return YES;
}

- (void)completed				// on thread, subclasses to override then finally call super
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif
	[self performSelector:@selector(finish) onThread:self.thread withObject:nil waitUntilDone:NO];
}

- (void)failed					// on thread, subclasses to override then finally call super
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif
	[self performSelector:@selector(finish) onThread:self.thread withObject:nil waitUntilDone:NO];
}

- (void)finish
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif

	self.isFinished = YES;

	[self cancelTimer];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"ConOp[\"%@\"] isEx=%d ixFin=%d isCan=%d", _runMessage, _isExecuting, _isFinished, _isCancelled];
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
