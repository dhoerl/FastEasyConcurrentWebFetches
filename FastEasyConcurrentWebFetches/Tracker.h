//
// ObjectTracker (TM)
// Tracker.h
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


// Add "import "Tracker.h" to you pch file for easy usage

@interface Tracker : NSObject
@property (atomic, copy) NSString *msg;					// from factory creation
@property (atomic, assign) BOOL isMainThread;			// created on the main thread
@property (atomic, copy) NSString *objDescription;		// snapshot of object description when created
@property (atomic, strong) NSDate *objCreateDate;		// creation
@property (atomic, strong) Class objClass;				// Object class

// Designated factory Track creation
+ (instancetype)trackerWithObject:(id)someObject msg:(NSString *)someMsg;

+ (NSSet *)allTrackers;									// all
+ (NSSet *)allTrackersOfClass:(Class)classObject;		// all say NSArray (and subclasses of that)

+ (void)printSet:(NSSet *)set;							// convenience routine

@end
