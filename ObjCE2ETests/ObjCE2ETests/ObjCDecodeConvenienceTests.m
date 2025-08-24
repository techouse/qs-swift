@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"

/// Small Obj-C helpers to mirror Swift convenience semantics.
static NSDictionary * _Nullable Qs_DecodeOrNil(id _Nullable input, QsDecodeOptions * _Nullable opts) {
    NSError *err = nil;
    NSDictionary *out = [Qs decode:input options:opts error:&err];
    if (err != nil) { return nil; }
    return out;
}

static NSDictionary * Qs_DecodeOrEmpty(id _Nullable input, QsDecodeOptions * _Nullable opts) {
    NSDictionary *out = Qs_DecodeOrNil(input, opts);
    return out ?: @{};
}

static NSDictionary * Qs_DecodeOrDefault(id _Nullable input, QsDecodeOptions * _Nullable opts, NSDictionary * _Nonnull def) {
    NSDictionary *out = Qs_DecodeOrNil(input, opts);
    return out ?: def;
}

@interface ObjCDecodeConvenienceTests : XCTestCase
@end

@implementation ObjCDecodeConvenienceTests

- (void)test_decodeOrNil_success {
    QsDecodeOptions *o = [QsDecodeOptions new];
    NSDictionary *m = Qs_DecodeOrNil(@"a=1", o);
    XCTAssertNotNil(m);
    XCTAssertEqualObjects(m[@"a"], @"1");
}

- (void)test_decodeOrNil_failure_returnsNil_andErrorHasDecodeDomain {
    QsDecodeOptions *o = [QsDecodeOptions new];
    o.strictDepth = YES; // enforce throwing on overflow
    o.depth = 2;
    
    // This key has 3 bracket groups → exceeds depth=2 in a well‑formed way and should throw.
    NSError *err = nil;
    NSDictionary *raw = [Qs decode:@"a[b][c][d]=x" options:o error:&err];
    XCTAssertNil(raw);
    XCTAssertNotNil(err);
    
    // Our convenience mirror should return nil on the same input.
    NSDictionary *m = Qs_DecodeOrNil(@"a[b][c][d]=x", o);
    XCTAssertNil(m);
    
    // Sanity: error domain/code and attached metadata.
    XCTAssertEqualObjects(err.domain, QsDecodeErrorInfo.domain);
    // depthExceeded maps to rawValue 4 (see QsDecodeErrorCodeObjC).
    XCTAssertEqual(err.code, 4);
    NSNumber *maxDepth = err.userInfo[QsDecodeErrorInfo.maxDepthKey];
    XCTAssertEqual(maxDepth.intValue, 2);
}

- (void)test_decodeOrEmpty_success_and_failureFallback {
    QsDecodeOptions *o = [QsDecodeOptions new];
    
    NSDictionary *ok = Qs_DecodeOrEmpty(@"a=1", o);
    XCTAssertEqualObjects(ok[@"a"], @"1");
    
    o.strictDepth = YES; o.depth = 2;
    NSDictionary *empty = Qs_DecodeOrEmpty(@"a[b][c][d]=x", o);
    XCTAssertEqual(empty.count, (NSUInteger)0);
}

- (void)test_decodeOrDefault_fallback_used_on_error {
    QsDecodeOptions *o = [QsDecodeOptions new];
    o.strictDepth = YES; o.depth = 2;
    
    NSDictionary *fallback = @{ @"fallback": @"yes" };
    NSDictionary *m = Qs_DecodeOrDefault(@"a[b][c][d]=x", o, fallback);
    XCTAssertEqualObjects(m, fallback);
}

- (void)test_decodeResult_semantics_success_and_failure {
    // Success branch
    QsDecodeOptions *okOpts = [QsDecodeOptions new];
    NSError *err1 = nil;
    NSDictionary *m1 = [Qs decode:@"a=1" options:okOpts error:&err1];
    XCTAssertNil(err1);
    XCTAssertEqualObjects(m1[@"a"], @"1");
    
    // Failure branch mirrors Swift's Result<Success, Failure>
    QsDecodeOptions *bad = [QsDecodeOptions new];
    bad.strictDepth = YES; bad.depth = 2;
    NSError *err2 = nil;
    NSDictionary *m2 = [Qs decode:@"a[b][c][d]=x" options:bad error:&err2];
    XCTAssertNil(m2);
    XCTAssertNotNil(err2);
    XCTAssertEqualObjects(err2.domain, QsDecodeErrorInfo.domain);
    XCTAssertEqual(err2.code, 4);
}

- (void)test_options_propagate_through_helpers_allowDots {
    QsDecodeOptions *o = [QsDecodeOptions new];
    o.allowDots = YES;
    
    NSDictionary *m = Qs_DecodeOrNil(@"a.b=c", o);
    XCTAssertNotNil(m);
    NSDictionary *a = m[@"a"];
    XCTAssertTrue([a isKindOfClass:NSDictionary.class]);
    XCTAssertEqualObjects(a[@"b"], @"c");
}

@end
