FastEasyConcurrentWebFetches (TM)
============================

Infrastructure to manage pools of web interface operations, elegant, simple, and quickly cancelable. Based on an earlier project that predated GCD, NSOperation-WebFetches-MadeEasy, it provides a lightweight framework for running multiple NSURLConnections, while providing the ability to rapidly cancel and cleanup for say, when the user taps the Back button.

This project demonstrates the OperationsRunner capability to easily handle asynchronous web fetches (and really any application where you need the ability to message background task). The core files are found in the WhatYouNeed folder, and the OperationsRunner.h file lists the handful of instructions to adopt it into any class you wish to use it in.

The demo app offers a few controls so that you can see for yourself that running operations can be cancelled and/or monitored.


UPDATES:

  1.0 (4/21/2013): First release
    - converted NSOperation-WebFetches-MadeEasy code from NSOperationQueues to GCD, leaving 90% of the old API intact
    - added a new 'start' method to ConcurrentOperations, so that any subclass to perform the necessary functionality

INTRO

Most of the complexity involved in managing a pool of concurrent NSURLConnections is moved to a helper class, OperationsRunner. By adding two methods to one of your classes, using a few of its methods, and implementing one protocol method, you can get all the benefits of background web fetches with just a small amount of effort. When each finishes, it messages your calling class in a single method, and returns the number of outstanding operations. When that value goes to zero, everything is done and you can then stop any spinner or other indicator you may be using.

This project also supplies the ConcurrentOperation base class, which deals with all the complexities of a concurrent operation. WebFetcher, a subclass of that, is provided to download web content. The final subclass of that, URfetcher, is similar to what you would write - it contains the critical call to connect::

	- (NSURLRequest *)setup
	{
		NSMutableURLRequest *request = [super setup];

		BOOL allOK = [self connect:request];
		return allOK ? request : nil;
	}

You can also build on ConcurrentOperation to do other features like sequencers that need to run in their own thread.

DEMO

Run the enclosed project, which downloads three files from my DropBox Public folder concurrently.

USAGE

- add the OperationsRunner and ConcurrentOp to your project

- review the instructions in OperationsRunner.h, and add the various includes and methods as instructed

OPERATION

When you want to fetch some data, you create a new ConcurrentOperation object, provide the URL of a resource (such as an image), and then message your class as:

    [myClass runOperation:op withMsg:@"Tracking string"];

The message parameter can take an arbitrary string or nil, however I strongly suggest you use a unique descriptive value. With debugging enabled, this string can get logged when the operation runs, when it completes, and the NSThread that runs the message is also tagged with it (did you know you can name NSThreads?)

When the operation completes, it messages your class on the main thread (unless you've configured it otherwise) as follows:

    [myClass operationFinished:(NSOperation *)op count:(NSUInteger)remainingCount];

Note that you don't even have to create the OperationsRunner - by using the NSObject method "forwardingTargetForSelector", the OperationsRunner gets created only when first messaged. This method also insures that the small set of messages destined for it get properly routed.

Suppose you need to cancel all operations, perhaps due to the user tapping the "Back" button. Simply message your class with:

    [operationsRunner cancelOperations];

You don't even need to do this! If you have active operations, when your class' dealloc is called, the OperationsRunner is also dealloced, and it properly tears down active operations.

The "operationFinished:count" method returns the remaining operation count, you can retire a spinner when it goes to zero. 
