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

#import "URSessionDelegate.h"

#define DEBUGGING	1	// 0 == no debug, 1 == lots of mesages

#if DEBUGGING == 1
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

@implementation URSessionDelegate

// Overriding the super methods

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                     willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                                     newRequest:(NSURLRequest *)request
                              completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [FECWF_OPERATIONSRUNNER fetcherForTask:task];

	LOG(@"YIKES: \"URLSession:willPerformHTTPRedirection:\"  resp=%@ newReq=%@ task=%@", response, request, fetcher.runMessage);

	if([[fetcher class] printDebugging]) LOG(@"Connection:willSendRequest %@ redirect %@", request, response);
	
	if(response) {
		LOG(@"RESP: status=%d headers=%@", [response statusCode], [response allHeaderFields]);
	}
	completionHandler(request);
}


- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                 didReceiveResponse:(NSURLResponse *)response
                                  completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [FECWF_OPERATIONSRUNNER fetcherForTask:dataTask];
LOG(@"YIKES: \"URLSession:didReceiveResponse:task:...\" fetcher=%@ response=%@", fetcher.runMessage, response);

	if(fetcher.isCancelled) {
		completionHandler(NSURLSessionResponseCancel);
#ifndef NDEBUG
		if([[self class] printDebugging]) LOG(@"Connection:cancelled!");
#endif
		return;
	}

	assert([response isKindOfClass:[NSHTTPURLResponse class]]);
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response; 
	fetcher.htmlStatus = [httpResponse statusCode];
#ifndef NDEBUG
	if(fetcher.htmlStatus != 200) {
		LOG(@"Server Response code %i url=%@", fetcher.htmlStatus, fetcher.urlStr);
		fetcher.errorMessage = [NSString stringWithFormat:@"Network Error %d %@",  fetcher.htmlStatus,[NSHTTPURLResponse localizedStringForStatusCode: fetcher.htmlStatus]];
		LOG(@"ERR: %@", fetcher.errorMessage);
	}
#endif
	if (fetcher.htmlStatus >= 500) {
		fetcher.errorMessage = [NSString stringWithFormat:@"Network Error %d %@", fetcher.htmlStatus,[NSHTTPURLResponse localizedStringForStatusCode:fetcher.htmlStatus]];
	}
	NSUInteger responseLength = response.expectedContentLength == NSURLResponseUnknownLength ? 1024 : (NSUInteger)response.expectedContentLength;
#ifndef NDEBUG
	if([[fetcher class] printDebugging]) LOG(@"Connection:didReceiveResponse: response=%@ len=%u", response, responseLength);
#endif

	// Must do this here, since we can get an error and still get data!
	fetcher.totalReceiveSize = responseLength;
	// NSLog(@"EXPECT SIZE %u", responseLength);
	fetcher.currentReceiveSize = 0;
	dispatch_queue_t q	= dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	fetcher.webData		= (NSData *)dispatch_data_create(NULL, 0, q, ^{});

	if(fetcher.errorMessage) {
		//LOG(@"Cancel due to error: %@", fetcher.errorMessage);
		completionHandler(NSURLSessionResponseCancel);
		fetcher.finalBlock(fetcher, NO);
	} else {
		//LOG(@"Proceed no error");
		completionHandler(NSURLSessionResponseAllow);
	}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(NSError *)error
{
	FECWF_WEBFETCHER *fetcher = [FECWF_OPERATIONSRUNNER fetcherForTask:task];
	if(fetcher.isCancelled) {
		return;
	}

	if(!fetcher.error && error) {
		fetcher.error = error;
		fetcher.errorMessage = [error localizedDescription];
	}
	
	// LOG(@"YIKES: \"URLSession:didCompleteWithError:task:...\" fetcher=%@ error=%@", fetcher.runMessage, error);
	fetcher.finalBlock(fetcher, fetcher.errorMessage ? NO : YES);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                     didReceiveData:(NSData *)data
{
	FECWF_WEBFETCHER *fetcher = [FECWF_OPERATIONSRUNNER fetcherForTask:dataTask];
	//LOG(@"YIKES: \"URLSession:didReceiveData:task:...\" fetcher=%@", fetcher.runMessage);

	fetcher.currentReceiveSize += [data length];
	fetcher.webData = (NSData *)dispatch_data_create_concat((dispatch_data_t)fetcher.webData, (dispatch_data_t)data);
}

@end
