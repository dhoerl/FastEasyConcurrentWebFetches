//
//  TestOperationProtocol.h
//  FastEasyConcurrentWebFetches
//
//  Created by David Hoerl on 4/25/13.
//  Copyright (c) 2013 dhoerl. All rights reserved.
//

typedef enum { atSetup, atStart, atFinish, atExit, atEnd } registrationStage;

@protocol TestOperationProtocol <NSObject>

- (void)register:(id)op atStage:(registrationStage)stage;

@end

