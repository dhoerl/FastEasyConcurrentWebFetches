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
@property(atomic, strong, readwrite) NSThread *thread;
@property(atomic, assign, readwrite) BOOL isCancelled;
@property(atomic, assign, readwrite) BOOL isExecuting;
@property(atomic, assign, readwrite) BOOL isFinished;

@end

@implementation ConcurrentOperation
{
	//NSTimer *__co_timer;		// so does not conflict with subclass
}
- (void)main
{

	if(self.isCancelled) {
		LOG(@"OPERATION %@ CANCELLED", _runMessage);
		return;
	}
	self.isExecuting = YES;

	id obj;
	BOOL allOK = NO;
	if((obj = [self setup])) {
		allOK = [self start:obj];
	}

	if(allOK) {
		// makes runloop functional
		NSTimer *__co_timer = [NSTimer scheduledTimerWithTimeInterval:60*60 target:self selector:@selector(timer:) userInfo:nil repeats:NO];

		while(!self.isFinished) {
			self.thread	= [NSThread currentThread];	// race condition
#ifndef NDEBUG
			BOOL ret = 
#endif
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
			assert(ret && "first assert");
			//LOG(@"%@ RUN_LOOP: isFinished=%d", self.runMessage, self.isFinished);
		}

		[__co_timer invalidate], __co_timer = nil;
	} else {
		[self finish];
	}

	self.isExecuting = NO;
	
	LOG(@"%@ LEAVE MAIN", _runMessage);
}

- (void)_OR_cancel
{
	//LOG(@"%@ _cancel: isFinished=%d", self.runMessage, self.isFinished);
	if(!self.isFinished) {
		self.isCancelled = YES;
		
		// can get cancelled while still in the queue, main not run yet so no thread
		[self performBlock:^(ConcurrentOperation *op)
			{
				[op cancel];
			}];
	}
}
- (void)cancel	// on thread
{
	//LOG(@"%@ cancel: isExecuting=%d", self.runMessage, self.isExecuting);
	if(self.isExecuting) {
		[self finish];
	}
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

- (void)finish					// on thread, subclasses to override then finally call super, for cleanup
{
	LOG(@"%@ finish: isFinished=%d", self.runMessage, self.isFinished);
	self.isFinished = YES;
}

- (void)dealloc
{
	LOG(@"%@ Dealloc: isExecuting=%d isFinished=%d isCancelled=%d", _runMessage, _isExecuting, _isFinished, _isCancelled);
#if VERIFY_DEALLOC	== 1
	if(_finishBlock) {
		_finishBlock();
	}
#endif
}

- (void)performBlock:(concurrentBlock)b
{
	NSThread *thread = self.thread;
	if(thread) {
		[self performSelector:@selector(runBlock:) onThread:thread withObject:b waitUntilDone:NO];
	} else {
		b(self);
	}

}
- (void)runBlock:(concurrentBlock)b
{
	b(self);
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"OP[\"%@\"]", _runMessage];
}

@end

