@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"

@interface ObjCEncodeConvenienceTests : XCTestCase
@end

/// Helpers that mimic Swift Qs.encodeOrNil / encodeOrEmpty using the Obj-C bridge.
static NSString * _Nullable Qs_EncodeOrNil(id _Nullable object, QsEncodeOptions * _Nullable options) {
    NSError *err = nil;
    NSString *out = [Qs encode:object options:options error:&err];
    return (err != nil) ? nil : out;
}

static NSString * Qs_EncodeOrEmpty(id _Nullable object, QsEncodeOptions * _Nullable options) {
    NSString *out = Qs_EncodeOrNil(object, options);
    return out ?: @"";
}

@implementation ObjCEncodeConvenienceTests

- (void)test_encodeOrNil_success_basic {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    NSDictionary *input = @{ @"a": @"1" };
    
    NSString *s = Qs_EncodeOrNil(input, opts);
    XCTAssertEqualObjects(s, @"a=1");
}

- (void)test_encodeOrEmpty_success_basic {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    NSDictionary *input = @{ @"a": @"1" };
    
    NSString *s = Qs_EncodeOrEmpty(input, opts);
    XCTAssertEqualObjects(s, @"a=1");
}

- (void)test_encodeOrNil_failure_cycle_returnsNil {
    // Create a tiny identity cycle: d1 → d2 → d1
    NSMutableDictionary *d1 = [NSMutableDictionary dictionary];
    NSMutableDictionary *d2 = [NSMutableDictionary dictionary];
    d1[@"x"] = d2;
    d2[@"y"] = d1;
    
    QsEncodeOptions *opts = [QsEncodeOptions new];
    
    // Convenience behavior: swallow error → return nil
    NSString *s = Qs_EncodeOrNil(d1, opts);
    XCTAssertNil(s);
    
    // Ground truth: bridge returns error domain for cyclic objects
    NSError *err = nil;
    NSString *direct = [Qs encode:d1 options:opts error:&err];
    XCTAssertNil(direct);
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, QsEncodeErrorInfo.domain);
    XCTAssertTrue([QsEncodeError isCyclicObject:err]);
    XCTAssertEqual(err.code, QsEncodeErrorCodeCyclicObject);
}

- (void)test_encodeOrEmpty_failure_cycle_returnsEmptyString {
    // Same cycle as above
    NSMutableDictionary *d1 = [NSMutableDictionary dictionary];
    NSMutableDictionary *d2 = [NSMutableDictionary dictionary];
    d1[@"x"] = d2;
    d2[@"y"] = d1;
    
    QsEncodeOptions *opts = [QsEncodeOptions new];
    
    // Convenience behavior: swallow error → return empty string
    NSString *s = Qs_EncodeOrEmpty(d1, opts);
    XCTAssertEqualObjects(s, @"");
}

- (void)test_encodeOrNil_respectsOptions_addQueryPrefix {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.addQueryPrefix = YES; // ensure options are honored by the convenience flow
    
    NSDictionary *input = @{ @"a": @"1" };
    NSString *s = Qs_EncodeOrNil(input, opts);
    XCTAssertEqualObjects(s, @"?a=1");
}

@end
