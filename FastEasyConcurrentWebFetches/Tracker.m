//
// ObjectTracker (TM)
// Tracker.m
// Copyright (C) 2013 by David Hoerl
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

#import "Tracker.h"

static NSMutableSet			*trackers;
static dispatch_semaphore_t	sema;

@interface Tracker ()
@property (atomic, assign) BOOL amDealloced;
@property (atomic, retain) NSValue *me;

@end

@implementation Tracker

+ (void)initialize
{
	trackers = [NSMutableSet setWithCapacity:10];
	sema = dispatch_semaphore_create(1);
}

+ (instancetype)trackerWithObject:(id)someObject msg:(NSString *)someMsg
{
	static BOOL opRunnerKey;

	Tracker *t = [Tracker new];
	t.objClass = [someObject class];
	t.objDescription = [someObject description];
	t.objCreateDate = [NSDate date];
	t.msg = someMsg;
	t.me = [NSValue valueWithNonretainedObject:t];
	t.isMainThread = [NSThread isMainThread];
	
	objc_setAssociatedObject(someObject, &opRunnerKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	[trackers addObject:t.me];
	dispatch_semaphore_signal(sema);
	
	return t;
}

+ (NSSet *)allTrackers
{
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	NSMutableSet *at = [NSMutableSet setWithCapacity:[trackers count]];
	[trackers enumerateObjectsUsingBlock:^(NSValue *v, BOOL *stop)
		{
			Tracker *t = (Tracker *)[v nonretainedObjectValue];
			[at addObject:t];
		} ];
	dispatch_semaphore_signal(sema);
	
	return at;
}

+ (NSSet *)allTrackersOfClass:(Class)classObject
{
	NSSet *at = [self allTrackers];
	
	NSMutableSet *atc = [NSMutableSet setWithCapacity:[at count]];
	[at enumerateObjectsUsingBlock:^(id obj, BOOL *stop)
		{
			if([obj isKindOfClass:classObject]) [atc addObject:obj];
		} ];

	return atc;
}

+ (void)printSet:(NSSet *)set
{
	[set enumerateObjectsUsingBlock:^(Tracker *t, BOOL *stop)
		{
			NSLog(@"%@", t);
		} ];
}

- (NSString *)description
{
	NSTimeInterval aliveTime = -[self.objCreateDate timeIntervalSinceNow];
	
	NSString *threadMsg;
	if([NSThread isMainThread]) {
		threadMsg = self.isMainThread ? @"" : @"thread: created background thread, now on main thread ";
	} else {
		threadMsg = self.isMainThread ? @"thread: created main thread thread, now on background thread " : @"";
	}
	
	NSString *str = [NSString stringWithFormat:@"%@ %@: %.3lfsec msg:%@ %@description: %@", NSStringFromClass(self.objClass), self.amDealloced ? @"lifetime" : @"alive", aliveTime, self.msg, threadMsg, self.objDescription];
	
	return str;
}

- (void)dealloc
{
	self.amDealloced = YES;
	NSLog(@"%@", self);

	NSValue *me = self.me;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^
		{
			dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
			//NSLog(@"trackerCnt=%d", [trackers count]);
			__block id obj;
			[trackers enumerateObjectsUsingBlock:^(NSValue *v, BOOL *stop)
				{
					if([v isEqualToValue:me]) {
						obj = v;
						*stop = YES;
					}
				} ];
			[trackers removeObject:obj];
			//NSLog(@"...trackerCnt=%d", [trackers count]);	// see it go to 0
			dispatch_semaphore_signal(sema);
		} );
}

@end
