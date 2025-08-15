// ObjCBridgeExtrasTests.m
@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"   // for SPMOrdered helpers
#define OD(KS,VS) [SPMOrdered dictWithKeys:(KS) values:(VS)]

@interface ObjCBridgeExtrasTests : XCTestCase
@end

@implementation ObjCBridgeExtrasTests

#pragma mark - Helpers

- (QsEncodeOptions *)optsNoEncode {
    QsEncodeOptions *o = [[QsEncodeOptions alloc] init];
    o.encode = NO;
    return o;
}

#pragma mark - 1) Cycles surface as NSError

- (void)test_encode_cycle_returnsNSError {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    m[@"self"] = m;  // cycle

    NSError *err = nil;
    NSString *s = [Qs encode:m options:nil error:&err];

    XCTAssertNil(s);
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, QsEncodeErrorInfo.domain);
    XCTAssertEqual(err.code, QsEncodeErrorCodeCyclicObject);
}

#pragma mark - 2) Custom value encoder block is invoked (values only)

- (void)test_valueEncoderBlock_is_called_for_values_only {
    QsEncodeOptions *o = [[QsEncodeOptions alloc] init];
    o.encode = YES;                 // normal percent-encoding
    o.encodeValuesOnly = YES;       // do NOT touch keys with the block
    o.valueEncoderBlock = ^NSString * _Nonnull(id value,
                                               NSNumber *charsetNum,
                                               NSNumber *formatNum) {
        // Make it obvious it ran:
        return @"VV";
    };

    NSString *got = [QsObjCTestHelpers encode:OD(@[@"a"], @[@"b"]) options:o];
    XCTAssertEqualObjects(got, @"a=VV");
}

#pragma mark - 3) Date serializer bridges through

- (void)test_dateSerializer_is_used {
    NSDate *epoch = [NSDate dateWithTimeIntervalSince1970:0];

    QsEncodeOptions *o = [[QsEncodeOptions alloc] init];
    o.dateSerializerBlock = ^NSString * _Nonnull(NSDate * _Nonnull date) {
        // return a plain string; the core will encode if needed
        return @"epoch";
    };

    NSString *got = [QsObjCTestHelpers encode:OD(@[@"when"], @[epoch]) options:o];
    XCTAssertEqualObjects(got, @"when=epoch");
}

#pragma mark - 4) Sort comparator controls top-level order

- (void)test_sortComparator_controls_key_order {
    QsEncodeOptions *o = [self optsNoEncode];
    o.sortComparatorBlock = ^NSInteger(id a, id b) {
        NSString *sa = [NSString stringWithFormat:@"%@", a ?: @""];
        NSString *sb = [NSString stringWithFormat:@"%@", b ?: @""];
        NSComparisonResult primary = [sa caseInsensitiveCompare:sb];
        if (primary != NSOrderedSame) return -primary;  // reverse
        NSComparisonResult tie = [sa compare:sb];
        return (tie == NSOrderedAscending) ? -1 : (tie == NSOrderedSame ? 0 : 1);
    };

    NSString *got = [QsObjCTestHelpers encode:[SPMOrdered dictWithKeys:@[@"a",@"b",@"c"] values:@[@"1",@"2",@"3"]]
                                      options:o];
    XCTAssertEqualObjects(got, @"c=3&b=2&a=1");
}

#pragma mark - 5) Function filter can drop a key via Undefined

- (void)test_functionFilter_drops_key_withUndefined {
    QsFunctionFilter *ff = [[QsFunctionFilter alloc] init:^id _Nullable(NSString *key, id value) {
        if ([key isEqualToString:@"secret"]) return [QsUndefined new]; // omit it
        return value;
    }];

    QsEncodeOptions *o = [self optsNoEncode];
    o.filter = [QsFilter function:ff];

    NSString *got = [QsObjCTestHelpers encode:[SPMOrdered dictWithKeys:@[@"ok", @"secret"] values:@[@"1", @"2"]]
                                      options:o];
    XCTAssertEqualObjects(got, @"ok=1");
}

#pragma mark - 6) Regex delimiter on decode

- (void)test_decode_with_regex_delimiter {
    QsDecodeOptions *d = [[QsDecodeOptions alloc] init];
    d.delimiter = QsDelimiter.commaOrSemicolon; // /\s*[,;]\s*/
    NSError *err = nil;

    NSDictionary *map = [Qs decode:@"a=1; b=2, c=3" options:d error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(map[@"a"], @"1");
    XCTAssertEqualObjects(map[@"b"], @"2");
    XCTAssertEqualObjects(map[@"c"], @"3");
}

#pragma mark - 7) Decode duplicates policy (combine/first/last)

- (void)test_decode_duplicates_policy {
    NSString *q = @"a=1&a=2";

    // combine → array
    QsDecodeOptions *d1 = [[QsDecodeOptions alloc] init];
    d1.duplicates = QsDuplicatesCombine;
    NSError *err = nil;
    NSDictionary *m1 = [Qs decode:q options:d1 error:&err];
    XCTAssertNil(err);
    id v1 = m1[@"a"]; XCTAssertTrue([v1 isKindOfClass:[NSArray class]]);
    NSArray *arr = (NSArray *)v1;
    XCTAssertEqual(arr.count, 2u);
    XCTAssertEqualObjects(arr[0], @"1");
    XCTAssertEqualObjects(arr[1], @"2");

    // first → "1"
    QsDecodeOptions *d2 = [[QsDecodeOptions alloc] init];
    d2.duplicates = QsDuplicatesFirst;
    NSDictionary *m2 = [Qs decode:q options:d2 error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(m2[@"a"], @"1");

    // last → "2"
    QsDecodeOptions *d3 = [[QsDecodeOptions alloc] init];
    d3.duplicates = QsDuplicatesLast;
    NSDictionary *m3 = [Qs decode:q options:d3 error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(m3[@"a"], @"2");
}

#pragma mark - 8) RFC1738 uses + for spaces when encoding

- (void)test_encode_rfc1738_space_plus {
    QsEncodeOptions *o = [self optsNoEncode];
    o.encode = YES;                  // allow percent-encoding
    o.format = QsFormatRfc1738;      // space → "+"
    NSString *got = [QsObjCTestHelpers encode:OD(@[@"q"], @[@"a b"]) options:o];
    XCTAssertEqualObjects(got, @"q=a+b");
}

#pragma mark - 9) Comma list format round-trip flag

- (void)test_encode_comma_list_roundtrip_flag {
    QsEncodeOptions *o = [self optsNoEncode];
    o.listFormat = @(QsListFormatComma);

    // roundTrip = YES → single-item lists get [] to re-inflate to array
    o.commaRoundTrip = YES;
    NSString *got = [QsObjCTestHelpers encode:OD(@[@"a"], @[@[ @"x" ]]) options:o];
    XCTAssertEqualObjects(got, @"a[]=x");

    // roundTrip = NO → single-item array encoded as scalar
    o.commaRoundTrip = NO;
    got = [QsObjCTestHelpers encode:OD(@[@"a"], @[@[ @"x" ]]) options:o];
    XCTAssertEqualObjects(got, @"a=x");
}

#pragma mark - 10) allowDots vs encodeDotInKeys

- (void)test_allowDots_vs_encodeDotInKeys {
    QsEncodeOptions *o = [self optsNoEncode];
    o.allowDots = NO; o.encodeDotInKeys = NO;

    // Use nested input so the encoder chooses between bracket vs dot notation.
    id nested = OD(@[@"a"], @[ OD(@[@"b"], @[@"1"]) ]);

    NSString *got = [QsObjCTestHelpers encode:nested options:o];
    XCTAssertEqualObjects(got, @"a[b]=1");

    o.allowDots = YES; // use dot notation for nested paths
    got = [QsObjCTestHelpers encode:nested options:o];
    XCTAssertEqualObjects(got, @"a.b=1");
}

#pragma mark - 11) Async wrappers call back on main

- (void)test_encode_async_on_main_queue {
    XCTestExpectation *exp = [self expectationWithDescription:@"encode-async-main"];
    QsEncodeOptions *o = [self optsNoEncode];
    [Qs encodeAsyncOnMain:OD(@[@"a"], @[@"b"]) options:o completion:^(NSString * _Nullable s, NSError * _Nullable err) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertNil(err);
        XCTAssertEqualObjects(s, @"a=b");
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:1.0];
}

- (void)test_decode_async_on_main_queue {
    XCTestExpectation *exp = [self expectationWithDescription:@"decode-async-main"];
    [Qs decodeAsyncOnMain:@"a=b" options:nil completion:^(NSDictionary * _Nullable dict, NSError * _Nullable err) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertNil(err);
        XCTAssertEqualObjects(dict[@"a"], @"b");
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:1.0];
}

#pragma mark - 12) Charset sentinel is present when requested

- (void)test_encode_includes_charset_sentinel_when_enabled {
    QsEncodeOptions *o = [self optsNoEncode];
    o.charsetSentinel = YES;
    o.encode = YES; // ensure sentinel token is encoded
    NSString *got = [QsObjCTestHelpers encode:OD(@[@"a"], @[@"b"]) options:o];
    // We don't assume position; just ensure the known token is present
    XCTAssertTrue([got containsString:@"utf8=%E2%9C%93"]);
}

#pragma mark - 13) skipNulls & Undefined omit keys

- (void)test_encode_skips_nulls_and_undefined {
    // NSNull + skipNulls
    QsEncodeOptions *o1 = [self optsNoEncode];
    o1.skipNulls = YES;
    NSString *got1 = [QsObjCTestHelpers encode:OD((@[@"a", @"b"]), (@[ [NSNull null], @"x" ])) options:o1];
    XCTAssertEqualObjects(got1, @"b=x");

    // Direct Undefined sentinel value
    QsEncodeOptions *o2 = [self optsNoEncode];
    NSString *got2 = [QsObjCTestHelpers encode:OD((@[@"a", @"b"]), (@[ [QsUndefined new], @"x" ])) options:o2];
    XCTAssertEqualObjects(got2, @"b=x");
}

#pragma mark - 14) Decode depth limit surfaces error when strict & throwing

- (void)test_decode_depth_exceeded_throws_when_strict {
    QsDecodeOptions *d = [[QsDecodeOptions alloc] init];
    d.depth = 1;                // allow one level; we'll exceed with two below
    d.strictDepth = YES;        // enforce exact depth
    d.throwOnLimitExceeded = YES;

    NSError *err = nil;
    NSDictionary *map = [Qs decode:@"a[b][c]=1" options:d error:&err];
    XCTAssertNil(map);
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, QsDecodeErrorInfo.domain);
    XCTAssertEqual(err.code, QsDecodeErrorCodeDepthExceeded);
}

#pragma mark - 15) valueEncoderBlock can encode keys when encodeValuesOnly = NO

- (void)test_valueEncoderBlock_encodes_keys_when_allowed {
    QsEncodeOptions *o = [self optsNoEncode];
    o.encode = YES;
    o.encodeValuesOnly = NO; // allow block for keys too
    o.valueEncoderBlock = ^NSString * _Nonnull(id value, NSNumber *charsetNum, NSNumber *formatNum) {
        return @"V"; // obvious marker
    };
    NSString *got = [QsObjCTestHelpers encode:OD(@[@"A"], @[@"b"]) options:o];
    XCTAssertEqualObjects(got, @"V=V");
}

@end
