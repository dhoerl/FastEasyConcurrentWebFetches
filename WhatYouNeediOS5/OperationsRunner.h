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

#import <objc/runtime.h>

#import "OperationsRunnerProtocol.h"
#import "ConcurrentOperation.h"

@protocol OperationsRunnerProtocol;

// DEFAULTS
#define DEFAULT_MAX_OPS					4						// Apple suggests a number like 4 for iOS, would not exceed 10, as each is a NSThread
#define DEFAULT_PRIORITY	DISPATCH_QUEUE_PRIORITY_DEFAULT		// both dispatch queues use this
#define DEFAULT_MILLI_SEC_CANCEL_DELAY	100

// how do you want the return message delivered
typedef enum { msgDelOnMainThread=0, msgDelOnAnyThread, msgOnSpecificThread, msgOnSpecificQueue } msgType;

@interface OperationsRunner : NSObject
@property (nonatomic, assign) msgType msgDelOn;					// how to message delegate, defaults to MainThread
@property (nonatomic, weak) NSThread *delegateThread;			// where to message delegate, sets msgDelOn->msgOnSpecificThread
@property (nonatomic, assign) dispatch_queue_t delegateQueue;	// where to message delegate, sets msgDelOn->msgOnSpecificQueue
@property (nonatomic, assign) dispatch_group_t delegateGroup;	// if set, use dispatch_group_async()
@property (nonatomic, assign) BOOL noDebugMsgs;					// suppress debug messages
@property (nonatomic, assign) long priority;					// targets the internal GCD queue doleing out the operations
@property (nonatomic, assign) NSUInteger maxOps;				// set the NSOperationQueue's maxConcurrentOperationCount
@property (nonatomic, assign) NSUInteger mSecCancelDelay;		// set the NSOperationQueue's maxConcurrentOperationCount

// These methods are for direct messaging. The reason cancelOperations is here is to prevent the creattion of an object, just to cancel it.
- (id)initWithDelegate:(id <OperationsRunnerProtocol>)del;		// designated initializer

@end

#if 0 

// 1) Add the protocol to the class extension interface (often in the interface file)
@interface MyClass () <OperationsRunnerProtocol>

// 2) Add the header to the implementation file
#import "OperationsRunner.h"

// 3) Add this method to the implementation file (I put it at the bottom, could go into a category too)
- (id)forwardingTargetForSelector:(SEL)sel
{
	if(
		sel == @selector(runOperation:withMsg:)	|| 
		sel == @selector(runOperations:)		||
		sel == @selector(operationsCount)		||
		sel == @selector(cancelOperations)		||
		sel == @selector(restartOperations)		||
		sel == @selector(operationsRunner)
	) {
		static BOOL myKey;
		id obj = objc_getAssociatedObject(self, &myKey);
		if(!obj) {
			if(sel == @selector(cancelOperations)) {
				// cancel sent in say dealloc, don't create an object just to release it
				obj = [OperationsRunner class];
			} else {
				// Object only created if needed. NOT THREAD SAFE (if you need that use a dispatch semaphone to insure only one object created
				obj = [[OperationsRunner alloc] initWithDelegate:self];
				objc_setAssociatedObject(self, &myKey, obj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				{
					// Set priorities once, or optionally you can ask [self operationsRunner] to get/create the item, and set/change these dynamically
					// OperationsRunner *OperationsRunner = (OperationsRunner *)obj;
					// operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;	// for example
					// operationsRunner.maxOps = 4;										// for example
					// operationsRunner.mSecCancelDelay = 10;							// for example
				}
			}
		}
		return obj;
	} else {
		return [super forwardingTargetForSelector:sel];
	}
}

// 4) Declare a category with these methods in the interface or implementation file (change MyClass to your class)
//    Put in your interface file if you want these to be used by other classes, or in the implementation to make them private
@interface MyClass (OperationsRunner)

- (OperationsRunner *)operationsRunner;				// get the current instance (or create it)
- (void)runOperation:(ConcurrentOperation *)op withMsg:(NSString *)msg;	// to submit an operation
- (BOOL)runOperations:(NSSet *)operations;			// Set of ConcurrentOperation objects with their runMessage set (or not)
- (NSUInteger)operationsCount;						// returns the total number of outstanding operations
- (BOOL)cancelOperations;							// stop all work, will not get any more delegate calls after it returns, returns YES if everything torn down properly
- (void)restartOperations;							// restart things

@end

#endif