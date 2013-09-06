//
//  URSessionDelegate.m
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 8/30/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
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
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];

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
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
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
	
	if(fetcher.errorMessage) {
		completionHandler(NSURLSessionResponseCancel);
		fetcher.finalBlock(fetcher, NO);
	} else {
		fetcher.totalReceiveSize = responseLength;
		fetcher.currentReceiveSize = 0;
		dispatch_queue_t q	= dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		fetcher.webData		= (NSData *)dispatch_data_create(NULL, 0, q, ^{});
		completionHandler(NSURLSessionResponseAllow);
	}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(NSError *)error
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];
	if(fetcher.isCancelled) {
		return;
	}
	// LOG(@"YIKES: \"URLSession:didCompleteWithError:task:...\" fetcher=%@ error=%@", fetcher.runMessage, error);
	if(!fetcher.error && error) {
		fetcher.error = error;
		fetcher.errorMessage = [error localizedDescription];
	}
	fetcher.finalBlock(fetcher, fetcher.errorMessage ? NO : YES);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                     didReceiveData:(NSData *)data
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
	//LOG(@"YIKES: \"URLSession:didReceiveData:task:...\" fetcher=%@", fetcher.runMessage);

	fetcher.currentReceiveSize += [data length];

	dispatch_queue_t q	= dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_data_t d	= dispatch_data_create([data bytes], [data length], q, ^{ CFDataRef cfData = CFBridgingRetain(data); CFRelease(cfData);} );
	fetcher.webData		= (NSData *)dispatch_data_create_concat((dispatch_data_t)fetcher.webData, d);
}

@end
