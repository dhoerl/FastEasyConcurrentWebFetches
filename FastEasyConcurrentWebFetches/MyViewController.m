
// FastEasyConcurrentWebFetches (TM)
// Copyright (C) 2012-2016 by David Hoerl
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


#import "OperationsRunner.h"
#import "OperationsRunnerProtocol.h"
#import "URfetcher.h"

static NSUInteger lastOperationsCount;
static NSUInteger lastMaxConcurrent;
static NSUInteger lastPriority;

// Add the protocol to the class extension interface in the implementation
@interface MyViewController () <FECWF_OPSRUNNER_PROTOCOL>
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
	OperationsRunner *opRunner;
}

+ (void)initialize
{
	lastOperationsCount	= 4;
	lastMaxConcurrent	= 2;
	lastPriority		= 1;
	

	FECWF_SESSION_DELEGATE *del = [FECWF_SESSION_DELEGATE new];
	
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.URLCache = nil;
assert(config.HTTPShouldSetCookies);
	config.HTTPShouldSetCookies = YES;
	config.HTTPShouldUsePipelining = YES;
	
	[FECWF_OPERATIONSRUNNER createSharedSessionWithConfiguration:config delegate:del];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
		opRunner = [[OperationsRunner alloc] initWithDelegate:self];
    }
    return self;
}
- (void)dealloc
{
	[opRunner cancelOperations];
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
				[opRunner runOperation:fetcher withMsg:msg];
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
	[opRunner cancelOperations];
	[opRunner restartOperations];
	
	[self defaultButtons];
}

- (IBAction)backAction:(id)sender
{
	[opRunner cancelOperations];	// good idea to do as soon as possible

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
	opRunner.maxOps = lastMaxConcurrent;
}

- (IBAction)priorityAction:(id)sender
{
	lastPriority = [(UISegmentedControl *)sender selectedSegmentIndex];

	qos_class_t val;
	switch(lastPriority) {
	case 0:	val = QOS_CLASS_USER_INTERACTIVE;	break;
	case 1:	val = QOS_CLASS_USER_INITIATED;	break;
	case 2:	val = QOS_CLASS_DEFAULT;			break;
	case 3:	val = QOS_CLASS_UTILITY;			break;
	case 4:	val = QOS_CLASS_BACKGROUND;			break;
	}
	opRunner.priority = val;
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

@end

