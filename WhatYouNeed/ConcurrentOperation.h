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

@interface ConcurrentOperation : NSObject
@property (nonatomic, copy) NSString *runMessage;		// debugging
@property (atomic, assign, readonly) BOOL isCancelled;
@property (atomic, assign, readonly) BOOL isExecuting;
@property (atomic, assign, readonly) BOOL isFinished;
#if defined(VERIFY_DEALLOC)
@property (nonatomic, strong) dispatch_block_t finishBlock;
#endif
#if defined(UNIT_TESTING)	// lets us force errors in code
@property (atomic, weak, readonly) NSThread *thread;
#endif
- (void)main;								// starting point

@end

// These are here for subclassers and not intended for general use
@interface ConcurrentOperation (ForSubClassesInternalUse)

- (id)setup;								// get the app started, object->continue, nil->failed so return
- (BOOL)start:(id)setupObject;				// called after setup has succeeded with the setup's returned value
- (void)completed;							// subclasses to override, call super
- (void)failed;								// subclasses to override then finally call super
- (void)finish;								// subclasses to override for cleanup, call super, only called if the operation successfully starts
- (void)cancel;								// for subclasses, called on operation's thread

@end