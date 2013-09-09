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

#import "ORSessionDelegate.h"

#define DEBUGGING	1	// 0 == no debug, 1 == lots of mesages

#if DEBUGGING == 1
#define LOG(...) NSLog(__VA_ARGS__)
#else
WTF
#define LOG(...)
#endif

@implementation ORSessionDelegate

#if DEBUGGING == 1

#pragma mark NSURLSessionDelegate  <NSObject>

/* The last message a session receives.  A session will only become
 * invalid because of a systemic error or when it has been
 * explicitly invalidated, in which case it will receive an
 * { NSURLErrorDomain, NSURLUserCanceled } error. 
 */
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
	LOG(@"YIKES: \"URLSession:didBecomeInvalidWithError:\"  invalidated!!!");
}

/* If implemented, when a connection level authentication challenge
 * has occurred, this delegate will be given the opportunity to
 * provide authentication credentials to the underlying
 * connection. Some types of authentication will apply to more than
 * one request on a given connection to a server (SSL Server Trust
 * challenges).  If this delegate message is not implemented, the 
 * behavior will be to use the default handling, which may involve user
 * interaction. 
 */
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
                                             completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
	LOG(@"YIKES: \"URLSession:didReceiveChallenge:(no task)...\"  challenge=%@", challenge);

}

/* If an application has received an
 * -application:handleEventsForBackgroundURLSession:completionHandler:
 * message, the session delegate will receive this message to indicate
 * that all messages previously enqueued for this session have been
 * delivered.  At this time it is safe to invoke the previously stored
 * completion handler, or to begin any internal updates that will
 * result in invoking the completion handler.
 */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
	LOG(@"YIKES: \"URLSessionDidFinishEventsForBackgroundURLSession\"");
}

#pragma mark NSURLSessionTaskDelegate <NSURLSessionDelegate>

/* An HTTP request is attempting to perform a redirection to a different
 * URL. You must invoke the completion routine to allow the
 * redirection, allow the redirection with a modified request, or
 * pass nil to the completionHandler to cause the body of the redirection 
 * response to be delivered as the payload of this request. The default
 * is to follow redirections. 
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                     willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                                     newRequest:(NSURLRequest *)request
                              completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];

	LOG(@"YIKES: \"URLSession:willPerformHTTPRedirection:\"  resp=%@ newReq=%@ task=%@", response, request, fetcher.runMessage);
}

/* The task has received a request specific authentication challenge.
 * If this delegate is not implemented, the session specific authentication challenge
 * will *NOT* be called and the behavior will be the same as using the default handling
 * disposition. 
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                            didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
                              completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];
	LOG(@"YIKES: \"URLSession:didReceiveChallenge:...\" challenge=%@ fetcher=%@", challenge, fetcher.runMessage);
}

/* Sent if a task requires a new, unopened body stream.  This may be
 * necessary when authentication has failed for any request that
 * involves a body stream. 
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                              needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];
	LOG(@"YIKES: \"URLSession:needNewBodyStream:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Sent periodically to notify the delegate of upload progress.  This
 * information is also available as properties of the task.
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                                didSendBodyData:(int64_t)bytesSent
                                 totalBytesSent:(int64_t)totalBytesSent
                       totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];
	LOG(@"YIKES: \"URLSession:didSendBodyData:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Sent as the last message related to a specific task.  Error may be
 * nil, which implies that no error occurred and this task is complete. 
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(NSError *)error
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:task];
	LOG(@"YIKES: \"URLSession:didCompleteWithError:task:...\" fetcher=%@ error=%@", fetcher.runMessage, error);
}

#pragma mark NSURLSessionDataDelegate <NSURLSessionTaskDelegate>

/* The task has received a response and no further messages will be
 * received until the completion block is called. The disposition
 * allows you to cancel a request or to turn a data task into a
 * download task. This delegate message is optional - if you do not
 * implement it, you can get the response as a property of the task.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                 didReceiveResponse:(NSURLResponse *)response
                                  completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
	LOG(@"YIKES: \"URLSession:didReceiveResponse:task:...\" fetcher=%@ response=%@", fetcher.runMessage, response);
}

/* Notification that a data task has become a download task.  No
 * future messages will be sent to the data task.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                              didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
	LOG(@"YIKES: \"URLSession:didBecomeDownloadTask:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Sent when data is available for the delegate to consume.  It is
 * assumed that the delegate will retain and not copy the data.  As
 * the data may be discontiguous, you should use 
 * [NSData enumerateByteRangesUsingBlock:] to access it.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                     didReceiveData:(NSData *)data
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
	LOG(@"YIKES: \"URLSession:didReceiveData:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Invoke the completion routine with a valid NSCachedURLResponse to
 * allow the resulting data to be cached, or pass nil to prevent
 * caching. Note that there is no guarantee that caching will be
 * attempted for a given resource, and you should not rely on this
 * message to receive the resource data.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                  willCacheResponse:(NSCachedURLResponse *)proposedResponse 
                                  completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:dataTask];
	LOG(@"YIKES: \"URLSession:willCacheResponse:task:...\" fetcher=%@", fetcher.runMessage);
}


/*
 * Messages related to the operation of a task that writes data to a
 * file and notifies the delegate upon completion.
 */
#pragma mark NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>

/* Sent when a download task that has completed a download.  The delegate should 
 * copy or move the file at the given location to a new location as it will be 
 * removed when the delegate message returns. URLSession:task:didCompleteWithError: will
 * still be called.
 */
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
                              didFinishDownloadingToURL:(NSURL *)location
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:downloadTask];
	LOG(@"YIKES: \"URLSession:didFinishDownloadingToURL:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Sent periodically to notify the delegate of download progress. */
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
                                           didWriteData:(int64_t)bytesWritten
                                      totalBytesWritten:(int64_t)totalBytesWritten
                              totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:downloadTask];
	LOG(@"YIKES: \"URLSession:didWriteData:task:...\" fetcher=%@", fetcher.runMessage);
}


/* Sent when a download has been resumed. If a download failed with an
 * error, the -userInfo dictionary of the error will contain an
 * NSURLSessionDownloadTaskResumeData key, whose value is the resume
 * data. 
 */
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
                                      didResumeAtOffset:(int64_t)fileOffset
                                     expectedTotalBytes:(int64_t)expectedTotalBytes
{
	FECWF_WEBFETCHER *fetcher = [OperationsRunner fetcherForTask:downloadTask];
	LOG(@"YIKES: \"URLSession:didResumeAtOffset:task:...\" fetcher=%@", fetcher.runMessage);
}

#endif

@end
