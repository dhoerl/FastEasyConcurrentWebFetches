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

#import "WebFetcher6.h"

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

// If you have some means to report progress
#define PROGRESS_OFFSET 0.25f
#define PROGRESS_UPDATE(x) ( ((x)*.75f)/(responseLength) + PROGRESS_OFFSET)

@interface WebFetcher ()
@property (atomic, assign, readwrite) BOOL isCancelled;
@property (atomic, assign, readwrite) BOOL isExecuting;
@property (atomic, assign, readwrite) BOOL isFinished;
@property (atomic, strong, readwrite) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong, readwrite) NSMutableData *webData;

@end

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

+ (BOOL)persistentConnection { return YES; }
+ (NSUInteger)timeout { return 60; }
+ (BOOL)printDebugging { return YES; }

- (BOOL)_OR_cancel:(NSUInteger)millisecondDelay
{
	BOOL ret = !self.isCancelled;
	if(ret) {
		self.isCancelled = YES;
		[self.connection cancel], self.connection = nil;
		[self cancel];
	}
	return YES;
}

- (void)cancel
{
	LOG(@"%@: got CANCEL", self);
	self.isFinished = YES;
}

- (NSMutableURLRequest *)setup
{
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
	LOG(@"%@ Start: isExecuting=%d", self.runMessage, self.isExecuting);

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

	_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
	[_connection setDelegateQueue:_operationQueue];
	if(_connection) self.isExecuting = YES;

	return _connection ? YES : NO;
}

- (void)completed // subclasses to override then finally call super
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"WF: completed");
#endif
	// we need a tad delay to let the completed return before the KVO message kicks in
	
	[self finish];
}

- (void)failed // subclasses to override then finally call super
{
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"WF: failed");
#endif

	[self finish];
}

- (void)finish
{
	self.isFinished = YES;
}

- (void)dealloc
{
	[_connection cancel];	// again, just to be 100% sure

#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"%@ Dealloc: isExecuting=%d isFinished=%d isCancelled=%d", _runMessage, _isExecuting, _isFinished, _isCancelled);
#endif
#ifdef VERIFY_DEALLOC
	if(_deallocBlock) {
		_deallocBlock();
	}
#endif
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"ConOp[\"%@\"] isEx=%d ixFin=%d isCan=%d", _runMessage, _isExecuting, _isFinished, _isCancelled];
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
	if(self.isCancelled) {
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
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:didReceiveData len=%lu %@", (unsigned long)[data length], [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
#endif
	if(self.isCancelled) {
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
#ifndef NDEBUG
	if([[self class] printDebugging]) LOG(@"Connection:connectionDidFinishLoading len=%u", [_webData length]);
#endif

	if(self.isCancelled) {
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