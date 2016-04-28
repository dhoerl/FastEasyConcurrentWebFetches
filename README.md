FastEasyConcurrentWebFetches (TM)
============================

An infrastructure of three classes to manage pools of web operations; elegant, simple, and quickly cancelable. Based on an earlier project that predated GCD (NSOperation-WebFetches-MadeEasy), it provides a lightweight framework for running multiple NSURLConnections (or other operations that require a delegate [iOS5 code only]), while providing the ability to cancel and cleanup when, for say, a user taps the Back button.

Users create new instances of a WebFetcher (or subclass), set its properties, then submits each individually or in batches using "[self runOperation:op runMsg:@"Some message to assist in debugging"]". When the operation finishes, you get it back on a delegate call "- (void)operationFinished:op count:remaininggCount", where you can see if it succeeded or failed, what the htmlStatus return was, retrieve and data or see if you had an error (NSError). The "remainingCount" is mostly to advise you when all outstanding operations have completed, to turn off spinners and say reenable the UI. At Lot18, I created about a dozen subclasses of WebFetchers, each for a specific type of REST interaction. Subclasses are often no more than tens of lines long, and build on the core infastructure.

This project includes a GUI test harness that uses hard wired web fetchers, which use HTTP GET to download an image from a public DropBox folder. The three core classes are found in the WhatYouNeed folder, and the OperationsRunner.h header file lists the handful of instructions required to adopt them into a project.

The demo app offers controls that vary the number of concurrent operations, the priority (target queue), and total number. Once these are active you can cancel them, or tap a 'Back' button, to see how quickly you can cancel and cleanup. A new compile time flag adds a verification step that all operations have in fact been deallocated.

This code, migrated from NSOperation-WebFetches-MadeEasy, was the basis of the Lot18 App (5 star rating), which often had hundreds of outstanding fetchers running getting product info, images, and posting user updates.

UPDATES:

  4.0.0 (4/20/2016): iOS8 and Swift
	- Swift annotations (project used in a number of Swift apps in the past year)
	- Switched to using QOS for dispatch queues
    - All the "WhatYouNeed" folders with versioned content now gone - just one left with NSURLSession support

  4.0.0 (9/2/2014): iOS8 and Swift
    - Swift usage brought complications to the iOS7 architecture of declaring a category in the interface, then using forwardingTargetForSelector: to redirect messages
    - Thus the new iOS8+ folder, which now requires you to declare a lazy OperationsRunner ivar, and message it directly
	- Only the WhatYouNeediOS8+ code base will be supported going forward.

  3.1.0 (2/9/2014): Session Restructure
    - 64bit clean
    - Moved ORSessionDelegate to RefSessionDelegate and URSessionDelegate to ORSessionDelegate. Your subclasses should use ORSessionDelegate as the base class. The RefSessionDelegate serves to provide method templates for every delegate method in the event you need one.
	- Several tweaks to make data handling more efficient.
	- This code now used in many of my projects, including a corporate framework being sent to numerous 3rd parties.
	- iOS6 code kept around for historical reasons, it's no longer maintained.
	- Add podspec for CocoaPods

  3.0 (9/6/2013): iOS7 Support
    - modified the components to use NSURLSession (Data Task mode, no background conversion yet).
	- the interface to OperationsRunner stayed the same, new class method to create a shared NSURLSession, connection object, delegate, and delegateQueue.
	- small changes to WebFetcher, it actually gets smaller since many functions moved to a shared delegate (ORSessionDeleage/URSessionDelegate). Lots of NSLogs in the delegates, all implemented in ORSessionDelegate for copy and paste into URSessionDelegate [get it UR == Your].
  
  2.2 (5/10/2013): Fix Race Condition
    - the finalBlock could get run before the operation finished completed/failed + finish. Now these are serialized.
  
  2.1 (5/9/2013): Unit tests passing thousands of time over hours
    - continue to refine so that all 8 tests pass for thousands of test iterations, for both iOS5 and iOS6  
    - Provide MACRO names for all classes (poor man's namespace) to avoid potential name conflicts, better support Library use
    - Test App now enables dealloc testing, to insure that no matter whether operations finish or get cancelled, that in the end they all get released
  
  2.0 (5/6/2013): Massive re-write with Unit Tests
    - Created two folders of needed files, one for iOS5 the other for iOS6
	- iOS5 uses the preexisiting runloop sleeping, and was migrated from NSOperations to pure blocks
	- code labeled iOS5 still works in iOS6, but the iOS6 specific code should require less resources
	- iOS6 drops ConcurrentOperations, uses WebFetchers as the base operation class, and uses the now working setDelegateQueue: method for delegate callbacks
	- 8 unit tests that work for both iOS5 and iOS6
	- integration steps reduced from 6 to 4, no need for even an ivar now

  1.1 (4/23/2013): Improved diagnostics
    - new compile time flag VERIFY_DEALLOC does a final test to verify all operations have been dealloced
	- new 'start' method removes the need to send a 'connect:' message in the 'setup' method

  1.0 (4/21/2013): First release
    - converted NSOperation-WebFetches-MadeEasy code from NSOperationQueues to GCD, leaving 90% of the old API intact
    - added a new 'start' method to ConcurrentOperations, so that any subclass to perform the necessary functionality

INTRO

Most of the complexity involved in managing a pool of concurrent NSURLConnections is moved to a helper class, OperationsRunner. By adding two methods to one of your classes, using a few of its methods, and implementing one protocol method, you can get all the benefits of background web fetches with just a small amount of effort. When each finishes, it messages your calling class in the sole protocol method, and supplies the number of remianing operations. When that value goes to zero, everything is done and you can then stop any spinner or other indicator you may be using. The reply message defaults to the main thread, but you can specify a specific thread, permit any thread, or supply a dispatch serial queue (and optional group).

This project also supplies the base class, which deals with all the complexities of a web interaction. The final subclass of that, URfetcher, is similar to what you would write.

DEMO

Run the enclosed project, which downloads a file from my DropBox Public folder concurrently.

USAGE

- add the OperationsRunner and ConcurrentOp to your project

- review the instructions in OperationsRunner.h, and add the various includes and methods as instructed

OPERATION

When you want to fetch some data, you create a new WebFetcher object, provide the URL of a resource (such as an image), and then message your class as:

    [self runOperation:op withMsg:@"Tracking string"];

The message parameter can take an arbitrary string or nil, however I strongly suggest you use a unique descriptive value. With debugging enabled, this string can get logged when the operation runs.

When the operation completes, it messages your class on the main thread (unless you've configured it otherwise) as follows:

    [myClass operationFinished:(NSOperation *)op count:(NSUInteger)remainingCount];

Note that you don't even have to create the OperationsRunner - by using the NSObject method "forwardingTargetForSelector", the OperationsRunner gets created only when first messaged. This method also insures that the small set of messages destined for it get properly routed.

Suppose you need to cancel all operations, perhaps due to the user tapping the "Back" button. Simply message your class with:

    [operationsRunner cancelOperations];

You don't even need to do this! If you have active operations, when your class' dealloc is called, the OperationsRunner is also dealloced, and it properly tears down active operations.

The "operationFinished:count" method returns the remaining operation count, you can retire a spinner when it goes to zero.

NOTES:

1) the reason for the 'forwardingTargetForSelector' design is that you can easily incorporate this into a UIVIewController base subclass, and subclasses have total access to the functionality using "self".

2) adding this to a base class consumes no resources, as the object is not created until used.

3) by adding the category interface definitions to a class' interface file, other objects can also send operations to it directly.
