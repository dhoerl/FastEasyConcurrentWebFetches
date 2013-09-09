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

#ifndef FECWF_WEBFETCHER
#define FECWF_WEBFETCHER WebFetcher
#endif

// Unit Testing
#if defined(UNIT_TESTING) && !defined(FORCE_MODE)
typedef enum { forcingOff=0, failAtSetup, failAtStartup, forceSuccess, forceFailure, forceRetry } forceMode;
#endif

@class FECWF_WEBFETCHER;
typedef void(^finishBlock)(FECWF_WEBFETCHER *op, BOOL succeeded);

@interface FECWF_WEBFETCHER : NSObject
@property (atomic, assign, readonly) BOOL isCancelled;
@property (atomic, assign, readonly) BOOL isExecuting;
@property (atomic, assign, readonly) BOOL isFinished;
@property (atomic, strong, readonly) NSURLConnection *connection;
@property (nonatomic, copy) NSString *runMessage;		// debugging
@property (nonatomic, copy) NSString *urlStr;
@property (nonatomic, strong, readonly) NSMutableData *webData;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) NSUInteger htmlStatus;

#ifdef VERIFY_DEALLOC
@property (nonatomic, strong) dispatch_block_t deallocBlock;
#endif

#if defined(UNIT_TESTING)
@property (nonatomic, assign) forceMode forceAction;
#endif

+ (BOOL)printDebugging;
+ (BOOL)persistentConnection;
+ (NSUInteger)timeout;

- (NSMutableURLRequest *)setup;				// get the app started, object->continue, nil->failed so return
- (BOOL)connect:(NSURLRequest *)request;
- (BOOL)start:(NSMutableURLRequest *)request;// called after setup has succeeded with the setup's returned value
- (void)completed;							// subclasses to override, call super
- (void)failed;								// subclasses to override, call super
- (void)finish;								// subclasses to override for cleanup, call super, only called if the operation successfully starts
- (void)cancel;								// for subclasses, called on operation's thread

@end

@interface FECWF_WEBFETCHER () // Internal Use
@property (atomic, strong, strong) finishBlock finalBlock;
@end

@interface FECWF_WEBFETCHER (NSURLConnectionDelegate) <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end
