// NSURLRequest+HTTPBodyFix.m
//
// Copyright (C) 2016 Subito.it S.r.l (www.subito.it)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "include/NSURLRequest+HTTPBodyFix.h"
#import "include/SBTUITestTunnel.h"
#import "include/SBTSwizzleHelpers.h"
#import "include/SBTRequestPropertyStorage.h"

@implementation NSURLRequest (HTTPBodyFix)

- (NSData *)largeHTTPBody
{
    objc_getAssociatedObject(self, &SBTUITunneledNSURLProtocolLargeHTTPBodyKey);
}

- (void)setLargeHTTPBody:(NSData *)uploadHTTPBody
{
    objc_setAssociatedObject(self,
                             &SBTUITunneledNSURLProtocolLargeHTTPBodyKey,
                             uploadHTTPBody,
                             OBJC_ASSOCIATION_RETAIN);
}

- (NSData *)sbt_HTTPBodyStreamData;
{
    if (!self.HTTPBodyStream) {
        return nil;
    }
    
    if (self.HTTPBodyStream.streamStatus == NSStreamStatusClosed) {
        return self.largeHTTPBody;
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];

    BOOL shouldClose = (self.HTTPBodyStream.streamStatus == NSStreamStatusNotOpen);
    if (shouldClose) {
        [self.HTTPBodyStream open];
    }

    @try {
        NSInteger bytesRead;
        while ((bytesRead = [self.HTTPBodyStream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [data appendBytes:buffer length:bytesRead];
        }
        if (bytesRead < 0) {
            return nil;
        }
    } @finally {
        if (shouldClose) {
            [self.HTTPBodyStream close];
        }
    }
    
    self.largeHTTPBody = data;
    
    return data.length > 0 ? data : nil;
}

//- (BOOL)sbt_isUploadTaskRequest
//{
//    return ([SBTRequestPropertyStorage propertyForKey:SBTUITunneledNSURLProtocolIsUploadTaskKey inRequest:self] != nil);
//}
//
//- (void)sbt_markUploadTaskRequest
//{
//    NSAssert([self isKindOfClass:[NSMutableURLRequest class]], @"Attempted to mark an immutable request as an upload");
//
//    if ([self isKindOfClass:[NSMutableURLRequest class]]) {
//        [SBTRequestPropertyStorage setProperty:@YES forKey:SBTUITunneledNSURLProtocolIsUploadTaskKey inRequest:(NSMutableURLRequest *)self];
//    }
//}

- (NSURLRequest *)sbt_copyWithoutBody
{
    NSMutableURLRequest *modifiedRequest = [self mutableCopy];

    // clear the body and assume callers are providing that data elsewhere
    modifiedRequest.HTTPBody = nil;
    modifiedRequest.HTTPBodyStream = nil;

    // retain the original mutability
    if ([self isKindOfClass:[NSMutableURLRequest class]]) {
        return modifiedRequest;
    } else {
        return [modifiedRequest copy];
    }
}

// MARK: -

- (NSData *)swz_HTTPBody
{
//    // upload tasks will trigger a runtime warning if their body is non-nil, see note above
//    if ([self sbt_isUploadTaskRequest]) {
//        return nil;
//    }

    return [self swz_HTTPBody];
        
    //return ret ?: self.largeHTTPBody;
}

- (id)swz_copyWithZone:(NSZone *)zone
{
    NSMutableURLRequest *ret = [self mutableCopy];
    ret.largeHTTPBody = self.largeHTTPBody;
    return [ret swz_copyWithZone:zone];
}

- (id)swz_mutableCopyWithZone:(NSZone *)zone
{
    NSMutableURLRequest *ret = [self swz_mutableCopyWithZone:zone];
    ret.largeHTTPBody = self.largeHTTPBody;
    return ret;
}

- (id)portableCopy
{
    NSMutableURLRequest *mutableCopy = [self mutableCopy];
    //[NSURLProtocol removePropertyForKey:SBTUITunneledNSURLProtocolIsUploadTaskKey inRequest:mutableCopy];
    //[NSURLProtocol removePropertyForKey:SBTUITunneledNSURLProtocolLargeHTTPBodyKey inRequest:mutableCopy];
    mutableCopy.HTTPBody = mutableCopy.HTTPBody ?: self.largeHTTPBody;
    return [mutableCopy copy];
}

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SBTTestTunnelInstanceSwizzle(self.class, @selector(HTTPBody), @selector(swz_HTTPBody));
        SBTTestTunnelInstanceSwizzle(self.class, @selector(copyWithZone:), @selector(swz_copyWithZone:));
        SBTTestTunnelInstanceSwizzle(self.class, @selector(mutableCopyWithZone:), @selector(swz_mutableCopyWithZone:));
    });
}

- (nullable NSData *)sbt_extractHTTPBody
{
    if ([self HTTPBody]) {
        return [self HTTPBody];
    } else if (self.largeHTTPBody) {
        return self.largeHTTPBody;
    } else if (self.sbt_HTTPBodyStreamData) {
        return self.sbt_HTTPBodyStreamData;
    }
    return nil;
}

@end
