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

#if 0	// 1 == no debug, 0 == lots of mesages
#define LOG(...) 
#else
#define LOG(...) NSLog(__VA_ARGS__)
#endif

@interface ConcurrentOperation (DoesNotExist)

- (void)timer:(NSTimer *)t; // keep the compiler happy with an unfullfilled promise

@end

@interface ConcurrentOperation ()
@property(nonatomic, strong) NSTimer *timer;
@property(atomic, strong, readwrite) NSThread *thread;
//@property(atomic, assign) BOOL done;
@property(atomic, assign, readwrite) BOOL isCancelled;
@property(atomic, assign, readwrite) BOOL isExecuting;
@property(atomic, assign, readwrite) BOOL isFinished;

@end

@implementation ConcurrentOperation

- (void)main
{
	if(self.isCancelled) {
		// LOG(@"OPERATION CANCELLED: isCancelled=%d isHostUp=%d", isCancelled, isHostUDown);
		return;
	}
	self.isExecuting = YES;
	self.thread	= [NSThread currentThread];

	id obj;
	BOOL allOK = NO;
	if((obj = [self setup])) {
		allOK = [self start:obj];
	}

	if(allOK) {
		while(!self.isFinished) {
#ifndef NDEBUG
			BOOL ret = 
#endif
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
			assert(ret && "first assert");
			//LOG(@"%@ RUN_LOOP: isFinished=%d", self.runMessage, self.isFinished);
		}
	} else {
		[self finish];
	}

	[self cleanup];

	self.isExecuting = NO;
	
	//Log(@"%@ LEAVE MAIN", _runMessage);
}

- (void)_cancel
{
	//LOG(@"%@ _cancel: isFinished=%d", self.runMessage, self.isFinished);
	if(!self.isFinished) {
		self.isCancelled = YES;
		[self performSelector:@selector(cancel) onThread:self.thread withObject:nil waitUntilDone:NO];
	}
}
- (void)cancel
{
	//LOG(@"%@ cancel: isExecuting=%d", self.runMessage, self.isExecuting);
	if(self.isExecuting) {
		[self finish];
	}
}

- (id)setup
{
	// makes runloop functional
	self.timer = [NSTimer scheduledTimerWithTimeInterval:60*60 target:self selector:@selector(timer:) userInfo:nil repeats:NO];

	return @"";
}

- (BOOL)start:(id)setupObject
{
	//LOG(@"%@ start: isExecuting=%d", self.runMessage, self.isExecuting);

	return YES;
}

- (void)cleanup
{
	[_timer invalidate], _timer = nil;
	
	return;
}

- (void)completed // subclasses to override then finally call super
{
	[self finish];
}

- (void)failed // subclasses to override then finally call super
{
	[self finish];
}

- (void)finish // subclasses to override then finally call super, for cleanup
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

@end

