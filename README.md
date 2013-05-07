FastEasyConcurrentWebFetches (TM)
============================

An infrastructure of three classes to manage pools of web operations; elegant, simple, and quickly cancelable. Based on an earlier project that predated GCD (NSOperation-WebFetches-MadeEasy), it provides a lightweight framework for running multiple NSURLConnections (or other operations that require a delegate [iOS5 code]), while providing the ability to cancel and cleanup when, for say, a user taps the Back button.

This project includes a GUI test harness that uses hard wired web fetchers, which use HTTP GET to download an image from a public DropBox folder. The three core classes are found in the WhatYouNeed folder, and the OperationsRunner.h header file lists the handful of instructions required to adopt them into a project.

The demo app offers controls that vary the number of concurrent operations, the priority (target queue), and total number. Once these are active you can cancel them, or tap a 'Back' button, to see how quickly you can cancel and cleanup. A new compile time flag adds a verification step that all operations have in fact been deallocated.

This code, migrated from NSOperation-WebFetches-MadeEasy, was the basis of the Lot18 App (5 star rating), which often had hundreds of outstanding fetchers running getting product info, images, and posting user updates.

UPDATES:


  2.0 (5/??/2013): ** IN PROGRESS **
    - Provide MACRO names for all classes (poor man's namespace) to avoid potential name conflicts, better support Library use
  
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

Most of the complexity involved in managing a pool of concurrent NSURLConnections is moved to a helper class, OperationsRunner. By adding two methods to one of your classes, using a few of its methods, and implementing one protocol method, you can get all the benefits of background web fetches with just a small amount of effort. When each finishes, it messages your calling class in the sole protocol method, and supplies the number of remianing operations. When that value goes to zero, everything is done and you can then stop any spinner or other indicator you may be using. The reply message defaults to the main thread, but you can specify that a specific thread should be use, any thread, or supply a dispatch serial queue.

This project also supplies the FECWF_CONCURRENT_OPERATION base class, which deals with all the complexities of a concurrent operation. FECWF_WEBFETCHER, a subclass of that, is provided to download web content. The final subclass of that, URfetcher, is similar to what you would write.

You can also build on FECWF_CONCURRENT_OPERATION to do other features like sequencers that need to run in their own thread.

DEMO

Run the enclosed project, which downloads three files from my DropBox Public folder concurrently.

USAGE

- add the OperationsRunner and ConcurrentOp to your project

- review the instructions in OperationsRunner.h, and add the various includes and methods as instructed

OPERATION

When you want to fetch some data, you create a new FECWF_CONCURRENT_OPERATION object, provide the URL of a resource (such as an image), and then message your class as:

    [myClass runOperation:op withMsg:@"Tracking string"];

The message parameter can take an arbitrary string or nil, however I strongly suggest you use a unique descriptive value. With debugging enabled, this string can get logged when the operation runs, when it completes, and the NSThread that runs the message is also tagged with it (did you know you can name NSThreads?)

When the operation completes, it messages your class on the main thread (unless you've configured it otherwise) as follows:

    [myClass operationFinished:(NSOperation *)op count:(NSUInteger)remainingCount];

Note that you don't even have to create the OperationsRunner - by using the NSObject method "forwardingTargetForSelector", the OperationsRunner gets created only when first messaged. This method also insures that the small set of messages destined for it get properly routed.

Suppose you need to cancel all operations, perhaps due to the user tapping the "Back" button. Simply message your class with:

    [operationsRunner cancelOperations];

You don't even need to do this! If you have active operations, when your class' dealloc is called, the OperationsRunner is also dealloced, and it properly tears down active operations.

The "operationFinished:count" method returns the remaining operation count, you can retire a spinner when it goes to zero. 
