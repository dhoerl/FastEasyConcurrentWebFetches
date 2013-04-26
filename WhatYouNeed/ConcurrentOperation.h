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

#define VERIFY_DEALLOC	1	// define as "1" to verify all operations do in fact get dealloc'ed


@interface ConcurrentOperation : NSObject
@property (nonatomic, copy) NSString *runMessage;		// debugging
@property(atomic, assign, readonly) BOOL isCancelled;
@property(atomic, assign, readonly) BOOL isExecuting;
@property(atomic, assign, readonly) BOOL isFinished;

#if VERIFY_DEALLOC	== 1
@property (nonatomic, strong) dispatch_block_t finishBlock;
#endif

- (void)main;
- (void)cancel;											// for subclasses, called on operation's thread

@end

typedef void(^concurrentBlock)(ConcurrentOperation *op);

// These are here for subclassers and not intended for general use
@interface ConcurrentOperation (ForSubClassesInternalUse)

- (id)setup;								// get the app started, object->continue, nil->failed so return
- (BOOL)start:(id)setupObject;				// called after setup has succeeded with the setup's returned value
- (void)completed;							// subclasses to override, call super
- (void)failed;								// subclasses to override then finally call super
- (void)finish;								// subclasses to override for cleanup, call super
- (void)performBlock:(concurrentBlock)b;	// subclass, to run it on the appropriate thread

@end

