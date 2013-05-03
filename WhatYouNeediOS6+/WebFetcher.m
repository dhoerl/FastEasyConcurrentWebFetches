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

#import "WebFetcher.h"

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

// If you have some means to report progress
#define PROGRESS_OFFSET 0.25f
#define PROGRESS_UPDATE(x) ( ((x)*.75f)/(responseLength) + PROGRESS_OFFSET)

@interface WebFetcher ()
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic, strong, readwrite) NSMutableData *webData;

@end

#if 0


@interface ConcurrentOperation ()
@property(atomic, assign, readwrite) BOOL isCancelled;
@property(atomic, assign, readwrite) BOOL isExecuting;
@property(atomic, assign, readwrite) BOOL isFinished;
#if defined(UNIT_TESTING)
@property(atomic, strong, readwrite) concurrentBlock block;
#endif

@end

@implementation ConcurrentOperation
{
	dispatch_semaphore_t semaphore;
}

- (instancetype)init
{
	if((self = [super init])) {
		semaphore = dispatch_semaphore_create(1);
	}
	return self;
}

- (void)main
{
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	if(!self.isCancelled) {
		id obj;
		if((obj = [self setup]) && [self start:obj]) {
			// makes runloop functional
			self.thread	= [NSThread currentThread];
#ifndef NDEBUG
			self.thread.name = _runMessage;
#endif
			self.isExecuting = YES;
			self.co_timer = [NSTimer scheduledTimerWithTimeInterval:60*60 target:self selector:@selector(timer:) userInfo:nil repeats:NO];

			//LOG(@"%@ enter loop: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			BOOL ret = YES;
			while(ret && !self.isFinished) {
				dispatch_semaphore_signal(semaphore);
				LOG(@"%@ RUN_LOOP: sleep...", self.runMessage);
				ret = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
				dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
				LOG(@"%@ RUN_LOOP: isFinished=%d isCancelled=%d", self.runMessage, self.isFinished, self.isCancelled);
			}
#if defined(UNIT_TESTING)
			if(self.block) {
				self.block(self);
			}
#endif
			[self cancelTimer];
			self.isExecuting = NO;
			self.thread = nil;

		}
		if(self.isCancelled) {
			[self cancel];
		}
	}
	dispatch_semaphore_signal(semaphore);	// so cancel and/or final block don't take a long time
}

- (void)cancelTimer
{
#ifndef NDEBUG
	if(self.co_timer) assert([NSThread currentThread] == self.thread);
#endif
	[self.co_timer invalidate], self.co_timer = nil;
}

- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay
{
	self.isCancelled = YES;

	BOOL ret = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, millisecondDelay*NSEC_PER_MSEC)) ? NO : YES;
	if(ret) {
		if(self.isExecuting && !self.isFinished) {
			LOG(@"%@: send cancel", self.runMessage);
			self.isFinished = YES;	// redundant
			[self performSelector:@selector(cancel) onThread:self.thread withObject:nil waitUntilDone:NO];
			ret = YES;
		}
		dispatch_semaphore_signal(semaphore);
	} else {
		LOG(@"%@ failed to get the locking semaphore in %u milliseconds", self, millisecondDelay);
	}
	return ret;
}

- (void)cancel
{
#ifndef NDEBUG
	if(self.co_timer) assert([NSThread currentThread] == self.thread);
#endif
	LOG(@"%@: got CANCEL", self);
	self.isFinished = YES;
	
	[self cancelTimer];
}

- (id)setup	// on thread
{
	return @"";
}

- (BOOL)start:(id)setupObject	// on thread
{
	LOG(@"%@ Start: isExecuting=%d", self.runMessage, self.isExecuting);
	return YES;
}

- (void)completed				// on thread, subclasses to override then finally call super
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif
	[self performSelector:@selector(finish) onThread:self.thread withObject:nil waitUntilDone:NO];
}

- (void)failed					// on thread, subclasses to override then finally call super
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif
	[self performSelector:@selector(finish) onThread:self.thread withObject:nil waitUntilDone:NO];
}

- (void)finish
{
#ifndef NDEBUG
	assert(self.co_timer);
	assert([NSThread currentThread] == self.thread);
#endif

	self.isFinished = YES;

	[self cancelTimer];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"ConOp[\"%@\"] isEx=%d ixFin=%d isCan=%d", _runMessage, _isExecuting, _isFinished, _isCancelled];
}

@end
#endif


@implementation WebFetcher
{
	NSUInteger responseLength;
}

+ (void)initialize
{
	NSURLCache *cache = [NSURLCache sharedURLCache];

	[cache setDiskCapacity:0];
	[cache setMemoryCapacity:0];
}

+ (BOOL)persistentConnection { return NO; }
+ (NSUInteger)timeout { return 60; }
+ (BOOL)printDebugging { return NO; }

- (NSMutableURLRequest *)setup
{
	id foo = [super setup];	// foo just a flag
	if(!foo) return nil;

	Class class = [self class];

#if defined(UNIT_TESTING)	// lets us force errors in code
	switch(_force) {
	case forceSuccess:
	{
		__weak __typeof__(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
			{
				weakSelf.htmlStatus = 200;
				weakSelf.webData = [NSMutableData dataWithCapacity:256];
				[weakSelf performSelector:@selector(completed) onThread:self.thread withObject:nil waitUntilDone:NO];
				//[weakSelf performBlock:^(ConcurrentOperation *op) { [op completed]; }];
			} );
	}	break;

	case forceFailure:
	{
		__weak __typeof__(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
			{
				weakSelf.htmlStatus = 400;
				[weakSelf performSelector:@selector(failed) onThread:weakSelf.thread withObject:nil waitUntilDone:NO];
				//[weakSelf performBlock:^(ConcurrentOperation *op) { [op failed]; }];
			} );
	} break;
	
	case forceRetry:
	{
		__weak __typeof__(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
			{
				weakSelf.error = [NSError errorWithDomain:@"NSURLErrorDomain" code:-1001 userInfo:@{ NSLocalizedDescriptionKey : @"timed out" }];	// Timeout
				weakSelf.errorMessage = @"Forced Failure";
				[weakSelf performSelector:@selector(failed) onThread:weakSelf.thread withObject:nil waitUntilDone:NO];
				//[weakSelf performBlock:^(ConcurrentOperation *op) { [op failed]; }];
			} );
	} break;

	default:
		assert(!"should never get here");
		break;
	}
#endif

	NSURL *url = [NSURL URLWithString:_urlStr];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:[class timeout]];
	if([class persistentConnection]) {
		[request setValue:@"Keep-Alive" forHTTPHeaderField:@"Connection"];
		[request setHTTPShouldUsePipelining:YES];
	}
	return request;
}

- (BOOL)start:(NSMutableURLRequest *)request
{
	BOOL allOK = [self connect:request];
	return allOK;
}

- (BOOL)connect:(NSURLRequest *)request
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"URLSTRING1=%@", [request URL]);
#endif

#if defined(UNIT_TESTING)	// lets us force errors in code
	return YES;
#endif

	assert(request);

	_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
	return _connection ? YES : NO;
}

- (void)cancel
{
	[_connection cancel];

	[super cancel];	// last
}

- (void)completed // subclasses to override then finally call super
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"WF: completed");
#endif
	// we need a tad delay to let the completed return before the KVO message kicks in
	
	[super completed];
}

- (void)failed // subclasses to override then finally call super
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"WF: failed");
#endif
	
	[super failed];
}

- (void)dealloc
{
	[self.connection cancel];	// again, just to be 100% sure

	LOG(@"%@ Dealloc: isExecuting=%d isFinished=%d isCancelled=%d", _runMessage, _isExecuting, _isFinished, _isCancelled);
#ifdef VERIFY_DEALLOC
	if(_finishBlock) {
		_finishBlock();
	}
#endif
}

@end

@implementation WebFetcher (NSURLConnectionDelegate)

- (NSURLRequest *)connection:(NSURLConnection *)_conn willSendRequest:(NSURLRequest *)request redirectResponse:(NSHTTPURLResponse *)redirectResponse	// NSURLResponse NSHTTPURLResponse
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:willSendRequest %@ redirect %@", request, redirectResponse);
	if(redirectResponse) {
		LOG(@"RESP: status=%d headers=%@", [redirectResponse statusCode], [redirectResponse allHeaderFields]);
	}
#endif

	return request;
}


- (void)connection:(NSURLConnection *)_conn didReceiveResponse:(NSURLResponse *)response
{
	if([super isCancelled]) {
		[_connection cancel];
#ifndef NDEBUG
		if([[self class] printDebugging]) LOG(@"Connection:cancelled!");
#endif
		return;
	}

	assert([response isKindOfClass:[NSHTTPURLResponse class]]);
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response; 
	_htmlStatus = [httpResponse statusCode];
#ifndef NDEBUG
	if(_htmlStatus != 200) {
		LOG(@"Server Response code %i url=%@", _htmlStatus, _urlStr);
		_errorMessage = [NSString stringWithFormat:@"Network Error %d %@", _htmlStatus,[NSHTTPURLResponse localizedStringForStatusCode:_htmlStatus]];
		LOG(@"ERR: %@", _errorMessage);
	}
#endif
	if (_htmlStatus >= 500) {
		_errorMessage = [NSString stringWithFormat:@"Network Error %d %@", _htmlStatus,[NSHTTPURLResponse localizedStringForStatusCode:_htmlStatus]];
	}
	responseLength = response.expectedContentLength == NSURLResponseUnknownLength ? 1024 : (NSUInteger)response.expectedContentLength;
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:didReceiveResponse: response=%@ len=%u", response, responseLength);
	if(_webData) LOG(@"YIKES: already created a _webData object!!! ?!?!?!?!?!??!?!?!??!?!?!?!?!?!??!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?!?");
#endif
	_webData = [NSMutableData dataWithCapacity:responseLength];
}

- (void)connection:(NSURLConnection *)_conn didReceiveData:(NSData *)data
{
//#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:didReceiveData len=%lu %@", (unsigned long)[data length], [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//#endif
	if([super isCancelled]) {
		[_connection cancel];
		return;
	}
	[_webData appendData:data];
}

- (void)connection:(NSURLConnection *)_conn didFailWithError:(NSError *)err
{
#ifndef NDEBUG
	//if([[self class] printDebugging])
	LOG(@"Connection: %@ didFailWithError: %@", _urlStr, [err description]);
#endif
	_error = err;

	[self failed];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)_conn
{
//#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:connectionDidFinishLoading len=%u", [_webData length]);
//#endif

	if([super isCancelled]) {
		[_connection cancel];
		return;
	}

	[self completed];
}

#if 0
- (void)_connection:(NSURLConnection *)conn willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	LOG(@"WILL: %@ %@ %@", challenge, challenge.proposedCredential, challenge.proposedCredential);
	[challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
}
//#endif
- (void)_connection:(NSURLConnection *)conn willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	LOG(@"WILL To %@", conn.currentRequest.URL);
    NSURLCredential *credential = [NSURLCredential credentialWithUser:@"dhoerl"
                                                             password:@"foo"
                                                          persistence:NSURLCredentialPersistenceForSession];
    [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];    
}
//#if 0

- (void)_connection:(NSURLConnection *)_connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
}

- (BOOL)_connection:(NSURLConnection *)_connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
	LOG(@"Space: %@", protectionSpace);
	
	return YES;
}

- (void)_connection:(NSURLConnection *)_connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	LOG(@"GOT %@", challenge);
	[[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
}
#endif

@end