
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

#import "MyViewController.h"


#define URL			@"http://dl.dropboxusercontent.com/u/60414145/Tyco.jpg"
//#define URL		@@"http:/www.apple.com/"


#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000
#import "OperationsRunner8.h"
#import "OperationsRunnerProtocol8.h"
#define FECWF_RUN_OPERATION_TYPE		FECWF_WEBFETCHER
#import "URfetcher8.h"
#import "ORSessionDelegate.h"
#elif __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
#import "OperationsRunner6.h"
#import "OperationsRunnerProtocol6.h"
#define FECWF_RUN_OPERATION_TYPE		FECWF_WEBFETCHER
#import "URfetcher6.h"
#else
#import "OperationsRunner.h"
#import "OperationsRunnerProtocol.h"
#import "URfetcher.h"
#define FECWF_RUN_OPERATION_TYPE		FECWF_CONCURRENT_OPERATION
#endif

static NSUInteger lastOperationsCount;
static NSUInteger lastMaxConcurrent;
static NSUInteger lastPriority;

// 2) Add the protocol to the class extension interface in the implementation
@interface MyViewController () <FECWF_OPSRUNNER_PROTOCOL>
@end

// 4) Declare a category with these methods in the interface file (ie public) (change MyClass to your class)
@interface MyViewController (FECWF_OPERATIONSRUNNER)

- (FECWF_OPERATIONSRUNNER *)operationsRunner;				// get the current instance (or create it)
- (void)runOperation:(FECWF_RUN_OPERATION_TYPE *)op withMsg:(NSString *)msg;	// to submit an operation
- (BOOL)runOperations:(NSOrderedSet *)operations;	// Set of FECWF_CONCURRENT_OPERATION objects with their runMessage set (or not)
- (NSUInteger)operationsCount;						// returns the total number of outstanding operations
- (BOOL)cancelOperations;							// stop all work, will not get any more delegate calls after it returns, returns YES if everything torn down properly
- (BOOL)restartOperations;							// restart things
- (BOOL)disposeOperations;							// dealloc the OperationsRunner (only needed for special cases where you really want to get rid of all helper objects)

@end

@implementation MyViewController
{
	IBOutlet UIButton *fetch;
	IBOutlet UIButton *cancel;
	IBOutlet UIButton *back;
	IBOutlet UISlider *operationCount;
	IBOutlet UILabel *operationsToRun;
	IBOutlet UILabel *operationsLeft;
	IBOutlet UIActivityIndicatorView *spinner;
	IBOutlet UISlider *maxConcurrent;
	IBOutlet UILabel *maxConcurrentText;
	IBOutlet UISegmentedControl *priority;
	IBOutlet UILabel *elapsedTime;

	NSDate *startDate;
}

+ (void)initialize
{
	lastOperationsCount	= 4;
	lastMaxConcurrent	= 2;
	lastPriority		= 1;
	
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000

	FECWF_SESSION_DELEGATE *del = [FECWF_SESSION_DELEGATE new];
	
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.URLCache = nil;
assert(config.HTTPShouldSetCookies);
	config.HTTPShouldSetCookies = YES;
	config.HTTPShouldUsePipelining = YES;
	
	[FECWF_OPERATIONSRUNNER createSharedSessionWithConfiguration:config delegate:del];
#endif
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
- (void)dealloc
{
	[self cancelOperations];
	// NSLog(@"Dealloc done!");
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	[self defaultButtons];
}

- (void)defaultButtons
{
	[self disable:NO control:fetch];
	[self disable:YES control:cancel];
	[self disable:NO control:operationCount];
	[self disable:NO control:fetch];
	[spinner stopAnimating];

	operationCount.value = lastOperationsCount;
	operationsToRun.text = [NSString stringWithFormat:@"%tu", lastOperationsCount];
	operationsLeft.text = @"0";

	maxConcurrent.value = lastMaxConcurrent;
	maxConcurrentText.text = [NSString stringWithFormat:@"%tu", lastMaxConcurrent];

	priority.selectedSegmentIndex = lastPriority;
	
	[self operationsAction:operationCount];
	[self concurrentAction:maxConcurrent];
	[self priorityAction:priority];
}

- (IBAction)fetchAction:(id)sender
{
	startDate = [NSDate date];

	[self disable:YES control:fetch];
	[self disable:NO control:cancel];
	[self disable:YES control:operationCount];
	[self disable:YES control:fetch];

	dispatch_async(dispatch_get_main_queue(), ^
		{
			[spinner startAnimating];

			NSUInteger count = lrintf([operationCount value]);
			operationsLeft.text = [NSString stringWithFormat:@"%tu", count];
			
#if 1
			for(NSUInteger i=0; i<count; ++i) {
				NSString *msg = [NSString stringWithFormat:@"URfetcher #%tu", i];
				URfetcher *fetcher = [URfetcher new];
				fetcher.urlStr = URL;
				[self runOperation:fetcher withMsg:msg];
			}
#else
			NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithCapacity:count];
			for(NSUInteger i=0; i<count; ++i) {
				NSString *msg = [NSString stringWithFormat:@"URfetcher #%tu", i];
				URfetcher *fetcher = [URfetcher new];
				fetcher.urlStr = URL;
				fetcher.runMessage = msg;
				[set addObject:fetcher];
			}
			[self runOperations:set];
#endif
		} );
}
- (IBAction)cancelAction:(id)sender
{
	[self cancelOperations];
	[self restartOperations];
	
	[self defaultButtons];
}

- (IBAction)backAction:(id)sender
{
	[self cancelOperations];	// good idea to do as soon as possible

	[self dismissViewControllerAnimated:YES completion:^{ ; }];
}

- (IBAction)operationsAction:(id)sender
{
	lastOperationsCount = (NSUInteger)lrintf([(UISlider *)sender value]);
	operationsToRun.text = [NSString stringWithFormat:@"%tu", lastOperationsCount];
}

- (IBAction)concurrentAction:(id)sender
{
	lastMaxConcurrent = (NSUInteger)lrintf([(UISlider *)sender value]);
	maxConcurrentText.text = [NSString stringWithFormat:@"%tu", lastMaxConcurrent];
	[self operationsRunner].maxOps = lastMaxConcurrent;
}

- (IBAction)priorityAction:(id)sender
{
	lastPriority = [(UISegmentedControl *)sender selectedSegmentIndex];

	qos_class_t val;
	switch(lastPriority) {
	case 0:	val = QOS_CLASS_USER_INTERACTIVE;	break;
// QOS_CLASS_USER_INITIATED
	default:
	case 1:	val = QOS_CLASS_DEFAULT;		break;
	
	case 2:	val = QOS_CLASS_UTILITY;			break;
	case 3:	val = QOS_CLASS_BACKGROUND;			break;
	}
	[self operationsRunner].priority = val;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)disable:(BOOL)disable control:(UIControl *)control
{
	control.enabled = !disable;
	control.alpha	= disable ? 0.50f : 1.0f;
}


- (void)operationFinished:(NSOperation *)op count:(NSUInteger)remainingOps
{
	operationsLeft.text = [NSString stringWithFormat:@"%d", (int)remainingOps ];
	
	URfetcher *fetcher = (URfetcher *)op;
	
	//NSLog(@"Operation %@: %@", (fetcher.webData && !fetcher.error) ? @"Completed" : @"FAILED", fetcher.runMessage);
	NSLog(@"Operation %@: %@", fetcher.runMessage, [NSString stringWithFormat:@"ERROR=%@ size=%tu", fetcher.error, [(NSData *)fetcher.webData length]]);
	
	if(!remainingOps) {
		elapsedTime.text = [NSString stringWithFormat:@"%.2f seconds", -[startDate timeIntervalSinceNow]];
		[self defaultButtons];
	}
}

// 4) Add this method to the implementation file
- (id)forwardingTargetForSelector:(SEL)sel
{
	static BOOL opRunnerKey;
	id obj = objc_getAssociatedObject(self, &opRunnerKey);
	// Look for common selectors first
	if(
		sel == @selector(runOperation:withMsg:)	|| 
		sel == @selector(runOperations:)		||
		sel == @selector(operationsCount)		||
		sel == @selector(operationsRunner)
	) {
		if(!obj) {
			if(sel == @selector(cancelOperations)) {
				// cancel sent in say dealloc, don't create an object just to release it
				obj = [FECWF_OPERATIONSRUNNER class];
			} else {
				// Object only created if needed. NOT THREAD SAFE (if you need that use a dispatch semaphone to insure only one object created
				obj = [[FECWF_OPERATIONSRUNNER alloc] initWithDelegate:self];
				objc_setAssociatedObject(self, &opRunnerKey, obj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				{
					// Set priorities once, or optionally you can ask [self operationsRunner] to get/create the item, and set/change these dynamically
					FECWF_OPERATIONSRUNNER *operationsRunner = (FECWF_OPERATIONSRUNNER *)obj;
					operationsRunner.maxOps = lastMaxConcurrent;
					[self priorityAction:priority];	// sets priority
					//operationsRunner.priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
					//operationsRunner.delegateQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
				}
			}
		}
		return obj;
	} else
	if(
		sel == @selector(cancelOperations)		||
		sel == @selector(restartOperations)		||
		sel == @selector(disposeOperations)
	) {
		if(!obj) {
			// cancel sent in say dealloc, don't create an object just to release it
			obj = [FECWF_OPERATIONSRUNNER class];
		} else {
			if(sel == @selector(disposeOperations)) {
				objc_setAssociatedObject(self, &opRunnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				// cancel sent in say dealloc, don't create an object just to release it
			}
		}
		return obj;
	} else {
		return [super forwardingTargetForSelector:sel];
	}
}
- (void)viewDidUnload {
	spinner = nil;
	elapsedTime = nil;
	[super viewDidUnload];
}

@end

