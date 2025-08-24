@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"

@interface ObjCExampleTests : XCTestCase
@end

@implementation ObjCExampleTests

#pragma mark - Simple examples

- (void)test_simple_decode {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=c" options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"c");
}

- (void)test_simple_encode {
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"c"} options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=c");
}

#pragma mark - Decoding • Maps

- (void)test_maps_nested {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"foo[bar]=baz" options:nil error:&err];
    XCTAssertNil(err);
    NSDictionary *foo = r[@"foo"];
    XCTAssertEqualObjects(foo[@"bar"], @"baz");
}

- (void)test_maps_uriEncodedKeys {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a%5Bb%5D=c" options:nil error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"b"], @"c");
}

- (void)test_maps_deepNest {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"foo[bar][baz]=foobarbaz"
                         options:nil
                           error:&err];
    XCTAssertNil(err);
    NSDictionary *foo = r[@"foo"];
    NSDictionary *bar = foo[@"bar"];
    XCTAssertEqualObjects(bar[@"baz"], @"foobarbaz");
}

- (void)test_maps_defaultDepthTrims {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[b][c][d][e][f][g][h][i]=j"
                         options:nil
                           error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    NSDictionary *b = a[@"b"];
    NSDictionary *c = b[@"c"];
    NSDictionary *d = c[@"d"];
    NSDictionary *e = d[@"e"];
    NSDictionary *f = e[@"f"];
    XCTAssertEqualObjects(f[@"[g][h][i]"], @"j");
}

- (void)test_maps_overrideDepth {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.depth = 1;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[b][c][d][e][f][g][h][i]=j"
                         options:opts
                           error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    NSDictionary *b = a[@"b"];
    XCTAssertEqualObjects(b[@"[c][d][e][f][g][h][i]"], @"j");
}

- (void)test_maps_parameterLimit {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.parameterLimit = 1;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=b&c=d" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"b");
    XCTAssertNil(r[@"c"]);
}

- (void)test_maps_ignorePrefix {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.ignoreQueryPrefix = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"?a=b&c=d" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"b");
    XCTAssertEqualObjects(r[@"c"], @"d");
}

- (void)test_maps_allowDots {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.allowDots = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a.b=c" options:opts error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"b"], @"c");
}

- (void)test_maps_decodeDotInKeys {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.decodeDotInKeys = YES; // implies allowDots
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"name%252Eobj.first=John&name%252Eobj.last=Doe"
                         options:opts
                           error:&err];
    XCTAssertNil(err);
    NSDictionary *nameObj = r[@"name.obj"];
    XCTAssertEqualObjects(nameObj[@"first"], @"John");
    XCTAssertEqualObjects(nameObj[@"last"], @"Doe");
}

- (void)test_maps_allowEmptyLists {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.allowEmptyLists = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"foo[]&bar=baz" options:opts error:&err];
    XCTAssertNil(err);
    NSArray *foo = r[@"foo"];
    XCTAssertNotNil(foo);
    XCTAssertEqual(foo.count, 0);
    XCTAssertEqualObjects(r[@"bar"], @"baz");
}

- (void)test_maps_duplicatesDefault {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"foo=bar&foo=baz" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *arr = r[@"foo"];
    XCTAssertEqual(arr.count, 2);
    XCTAssertEqualObjects(arr.firstObject, @"bar");
    XCTAssertEqualObjects(arr.lastObject, @"baz");
}

- (void)test_maps_duplicatesModes {
    NSError *err = nil;
    
    QsDecodeOptions *c = [QsDecodeOptions new];
    c.duplicates = QsDuplicatesCombine;
    NSDictionary *r = [Qs decode:@"foo=bar&foo=baz" options:c error:&err];
    XCTAssertNil(err);
    XCTAssertEqual([r[@"foo"] count], 2);
    
    QsDecodeOptions *f = [QsDecodeOptions new];
    f.duplicates = QsDuplicatesFirst;
    r = [Qs decode:@"foo=bar&foo=baz" options:f error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"foo"], @"bar");
    
    QsDecodeOptions *l = [QsDecodeOptions new];
    l.duplicates = QsDuplicatesLast;
    r = [Qs decode:@"foo=bar&foo=baz" options:l error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"foo"], @"baz");
}

#pragma mark - Decoding • Lists

- (void)test_lists_brackets {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[]=b&a[]=c" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a = r[@"a"];
    XCTAssertEqual(a.count, 2);
    XCTAssertEqualObjects(a.firstObject, @"b");
    XCTAssertEqualObjects(a.lastObject, @"c");
}

- (void)test_lists_indices {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[1]=c&a[0]=b" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a = r[@"a"];
    XCTAssertEqual(a.count, 2);
    XCTAssertEqualObjects(a[0], @"b");
    XCTAssertEqualObjects(a[1], @"c");
}

- (void)test_lists_compactSparse {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[1]=b&a[15]=c" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a = r[@"a"];
    XCTAssertEqual(a.count, 2);
    XCTAssertEqualObjects(a.firstObject, @"b");
    XCTAssertEqualObjects(a.lastObject, @"c");
}

- (void)test_lists_preserveEmptyStrings {
    NSError *err = nil;
    
    NSDictionary *r0 = [Qs decode:@"a[]=&a[]=b" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a0 = r0[@"a"];
    XCTAssertEqualObjects(a0[0], @"");
    XCTAssertEqualObjects(a0[1], @"b");
    
    NSDictionary *r1 = [Qs decode:@"a[0]=b&a[1]=&a[2]=c" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a1 = r1[@"a"];
    XCTAssertEqualObjects(a1[0], @"b");
    XCTAssertEqualObjects(a1[1], @"");
    XCTAssertEqualObjects(a1[2], @"c");
}

- (void)test_lists_highIndexToMap {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[100]=b" options:nil error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"100"], @"b");
}

- (void)test_lists_overrideListLimit0 {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.listLimit = 0;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[1]=b" options:opts error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"1"], @"b");
}

- (void)test_lists_disableParsing {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.parseLists = NO;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[]=b" options:opts error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"0"], @"b");
}

- (void)test_lists_mixedNotations {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[0]=b&a[b]=c" options:nil error:&err];
    XCTAssertNil(err);
    NSDictionary *a = r[@"a"];
    XCTAssertEqualObjects(a[@"0"], @"b");
    XCTAssertEqualObjects(a[@"b"], @"c");
}

- (void)test_lists_ofMaps {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a[][b]=c" options:nil error:&err];
    XCTAssertNil(err);
    NSArray *a = r[@"a"];
    NSDictionary *first = a.firstObject;
    XCTAssertEqualObjects(first[@"b"], @"c");
}

- (void)test_lists_commaOption {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.comma = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=b,c" options:opts error:&err];
    XCTAssertNil(err);
    NSArray *a = r[@"a"];
    XCTAssertEqualObjects(a, (@[ @"b", @"c" ]));
}

#pragma mark - Decoding • Primitive/Scalar

- (void)test_scalars_asStrings {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=15&b=true&c=null" options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"15");
    XCTAssertEqualObjects(r[@"b"], @"true");
    XCTAssertEqualObjects(r[@"c"], @"null");
}

#pragma mark - Null values

- (void)test_nulls_decodeEmptyStrings {
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a&b=" options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"");
    XCTAssertEqualObjects(r[@"b"], @"");
}

- (void)test_nulls_decodeStrictNulls {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.strictNullHandling = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a&b=" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertTrue([r[@"a"] isKindOfClass:[NSNull class]]);
    XCTAssertEqualObjects(r[@"b"], @"");
}

#pragma mark - Decoding • Maps (extras)

- (void)test_maps_customDelimiter_string {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.delimiter = [QsDelimiter semicolon];
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=b;c=d" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"b");
    XCTAssertEqualObjects(r[@"c"], @"d");
}

- (void)test_maps_regexDelimiter {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.delimiter = [QsDelimiter commaOrSemicolon]; // /[;,]/
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=b;c=d" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"b");
    XCTAssertEqualObjects(r[@"c"], @"d");
}

- (void)test_maps_latin1_charset {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=%A7" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"§");
}

- (void)test_maps_charsetSentinel_latin1 {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    opts.charsetSentinel = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"utf8=%E2%9C%93&a=%C3%B8"
                         options:opts
                           error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"ø");
}

- (void)test_maps_charsetSentinel_utf8 {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.charset = NSUTF8StringEncoding;
    opts.charsetSentinel = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"utf8=%26%2310003%3B&a=%F8"
                         options:opts
                           error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"ø");
}

- (void)test_maps_interpretNumericEntities_isoLatin1 {
    QsDecodeOptions *opts = [QsDecodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    opts.interpretNumericEntities = YES;
    NSError *err = nil;
    NSDictionary *r = [Qs decode:@"a=%26%239786%3B" options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(r[@"a"], @"☺");
}

#pragma mark - Encoding

- (void)test_encode_maps_basic {
    NSError *err = nil;
    NSString *s1 = [Qs encode:@{@"a" : @"b"} options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s1, @"a=b");
    
    QsEncodeOptions *opts = [QsEncodeOptions new];
    NSString *s2 = [Qs encode:@{@"a" : @{@"b" : @"c"}} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s2, @"a%5Bb%5D=c");
}

- (void)test_encode_disableEncoding_leavesBrackets {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @{@"b" : @"c"}} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a[b]=c");
}

- (void)test_encode_valuesOnly {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encodeValuesOnly = YES;
    NSError *err = nil;
    NSDictionary *input = @{
        @"a" : @"b",
        @"c" : @[ @"d", @"e=f" ],
        @"f" : @[ @[ @"g" ], @[ @"h" ] ]
    };
    NSString *s = [Qs encode:input options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=b&c[0]=d&c[1]=e%3Df&f[0][0]=g&f[1][0]=h");
}

- (void)test_encode_customEncoder {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.valueEncoderBlock =
    ^NSString *(id value, NSNumber *charsetNum, NSNumber *formatNum) {
        id v = value ?: @"";
        if ([v isKindOfClass:[NSString class]] &&
            [(NSString *)v isEqualToString:@"č"]) {
            return @"c";
        }
        return [NSString stringWithFormat:@"%@", v];
    };
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @{@"b" : @"č"}} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a[b]=c");
}

- (void)test_encode_listsDefault_indices_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @[ @"b", @"c", @"d" ]}
                     options:opts
                       error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a[0]=b&a[1]=c&a[2]=d");
}

- (void)test_encode_indicesFalse_repeatKey_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.indices = @(NO);
    opts.encode = NO;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @[ @"b", @"c", @"d" ]}
                     options:opts
                       error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=b&a=c&a=d");
}

- (void)test_encode_listFormats_all {
    NSError *err = nil;
    
    QsEncodeOptions *idx = [QsEncodeOptions new];
    idx.listFormat = @(QsListFormatIndices);
    idx.encode = NO;
    NSString *s1 = [Qs encode:@{@"a" : @[ @"b", @"c" ]} options:idx error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s1, @"a[0]=b&a[1]=c");
    
    QsEncodeOptions *br = [QsEncodeOptions new];
    br.listFormat = @(QsListFormatBrackets);
    br.encode = NO;
    NSString *s2 = [Qs encode:@{@"a" : @[ @"b", @"c" ]} options:br error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s2, @"a[]=b&a[]=c");
    
    QsEncodeOptions *rep = [QsEncodeOptions new];
    rep.listFormat = @(QsListFormatRepeatKey);
    rep.encode = NO;
    NSString *s3 = [Qs encode:@{@"a" : @[ @"b", @"c" ]} options:rep error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s3, @"a=b&a=c");
    
    QsEncodeOptions *cm = [QsEncodeOptions new];
    cm.listFormat = @(QsListFormatComma);
    cm.encode = NO;
    NSString *s4 = [Qs encode:@{@"a" : @[ @"b", @"c" ]} options:cm error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s4, @"a=b,c");
}

- (void)test_encode_bracketNotationForMaps_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    NSDictionary *input = @{@"a" : @{@"b" : @{@"c" : @"d", @"e" : @"f"}}};
    NSError *err = nil;
    NSString *s = [Qs encode:input options:opts error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[ @"a[b][c]=d", @"a[b][e]=f" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_allowDots_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.allowDots = YES;
    opts.encode = NO;
    NSDictionary *input = @{@"a" : @{@"b" : @{@"c" : @"d", @"e" : @"f"}}};
    NSError *err = nil;
    NSString *s = [Qs encode:input options:opts error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[ @"a.b.c=d", @"a.b.e=f" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_encodeDotInKeys_true {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.allowDots = YES; // required when encodeDotInKeys = YES
    opts.encodeDotInKeys = YES;
    NSError *err = nil;
    NSString *s =
    [Qs encode:@{@"name.obj" : @{@"first" : @"John", @"last" : @"Doe"}}
       options:opts
         error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[
        @"name%252Eobj.first=John", @"name%252Eobj.last=Doe"
    ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_allowEmptyLists_true_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.allowEmptyLists = YES;
    opts.encode = NO;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"foo" : @[], @"bar" : @"baz"}
                     options:opts
                       error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[ @"foo[]", @"bar=baz" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_emptyAndNull_values {
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @""} options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=");
}

- (void)test_encode_emptyCollections_emitEmptyString {
    NSError *err = nil;
    XCTAssertEqualObjects([Qs encode:@{@"a" : @[]} options:nil error:&err], @"");
    XCTAssertEqualObjects([Qs encode:@{@"a" : @{}} options:nil error:&err], @"");
    XCTAssertEqualObjects([Qs encode:@{@"a" : @[ @[] ]} options:nil error:&err],
                          @"");
    XCTAssertEqualObjects(
                          [Qs encode:@{@"a" : @{@"b" : @[]}} options:nil error:&err], @"");
    XCTAssertEqualObjects(
                          [Qs encode:@{@"a" : @{@"b" : @{}}} options:nil error:&err], @"");
}

- (void)test_encode_omitsUndefined_properties {
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : [NSNull null], @"b" : [QsUndefined new]}
                     options:nil
                       error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=");
}

- (void)test_encode_addQueryPrefix {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.addQueryPrefix = YES;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"b", @"c" : @"d"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertTrue([s hasPrefix:@"?"]);
    NSSet *parts = [NSSet
                    setWithArray:[[s substringFromIndex:1] componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[ @"a=b", @"c=d" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_overrideDelimiter_string {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.delimiter = @";";
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"b", @"c" : @"d"} options:opts error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@";"]];
    NSSet *expected = [NSSet setWithArray:@[ @"a=b", @"c=d" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_date_default_encodeFalse_ISO8601ms {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0.007];
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : date} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=1970-01-01T00:00:00.007Z");
}

- (void)test_encode_date_customMillis_encodeFalse {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    opts.dateSerializerBlock = ^NSString *(NSDate *d) {
        long long ms = llround([d timeIntervalSince1970] * 1000.0);
        return [NSString stringWithFormat:@"%lld", ms];
    };
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0.007];
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : date} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=7");
}

- (void)test_encode_sortKeys_withComparator {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    opts.sortComparatorBlock = ^NSInteger(id a, id b) {
        NSString *sa = a ? [NSString stringWithFormat:@"%@", a] : @"";
        NSString *sb = b ? [NSString stringWithFormat:@"%@", b] : @"";
        NSComparisonResult c = [sa compare:sb];
        if (c == NSOrderedAscending)
            return -1;
        if (c == NSOrderedDescending)
            return 1;
        return 0;
    };
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"c", @"z" : @"y", @"b" : @"f"}
                     options:opts
                       error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=c&b=f&z=y");
}

- (void)test_encode_filter_withFunction {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0.123];
    NSDictionary *input =
    @{@"a" : @"b", @"c" : @"d", @"e" : @{@"f" : date, @"g" : @[ @2 ]}};
    
    QsFunctionFilter *ff =
    [[QsFunctionFilter alloc] init:^id(NSString *prefix, id value) {
        if ([prefix isEqualToString:@"b"]) {
            return [QsUndefined new]; // drop
        } else if ([prefix isEqualToString:@"e[f]"]) {
            long long ms = llround([value timeIntervalSince1970] * 1000.0);
            return @(ms);
        } else if ([prefix isEqualToString:@"e[g][0]"]) {
            if ([value isKindOfClass:[NSNumber class]])
                return @([value intValue] * 2);
            return value;
        }
        return value;
    }];
    
    QsFilter *filter = [QsFilter function:ff];
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.encode = NO;
    opts.filter = filter;
    NSError *err = nil;
    NSString *s = [Qs encode:input options:opts error:&err];
    XCTAssertNil(err);
    NSSet *parts = [NSSet setWithArray:[s componentsSeparatedByString:@"&"]];
    NSSet *expected = [NSSet setWithArray:@[ @"a=b", @"c=d", @"e[f]=123", @"e[g][0]=4" ]];
    XCTAssertEqualObjects(parts, expected);
}

- (void)test_encode_filter_withIterable {
    NSError *err = nil;
    
    // Only keys a and e
    QsEncodeOptions *opts1 = [QsEncodeOptions new];
    opts1.encode = NO;
    opts1.filter = [QsFilter
                    iterable:[[QsIterableFilter alloc] initWithIterable:@[ @"a", @"e" ]]];
    NSString *s1 = [Qs encode:@{@"a" : @"b", @"c" : @"d", @"e" : @"f"}
                      options:opts1
                        error:&err];
    XCTAssertNil(err);
    NSSet *set1 = [NSSet setWithArray:[s1 componentsSeparatedByString:@"&"]];
    NSSet *expected1 = [NSSet setWithArray:@[ @"a=b", @"e=f" ]];
    XCTAssertEqualObjects(set1, expected1);
    
    // Mixed: only a, and indices 0 and 2 under a
    QsEncodeOptions *opts2 = [QsEncodeOptions new];
    opts2.encode = NO;
    opts2.filter = [QsFilter
                    iterable:[[QsIterableFilter alloc] initWithIterable:@[ @"a", @0, @2 ]]];
    NSString *s2 = [Qs encode:@{@"a" : @[ @"b", @"c", @"d" ], @"e" : @"f"}
                      options:opts2
                        error:&err];
    XCTAssertNil(err);
    NSSet *set2 = [NSSet setWithArray:[s2 componentsSeparatedByString:@"&"]];
    NSSet *expected2 = [NSSet setWithArray:@[ @"a[0]=b", @"a[2]=d" ]];
    XCTAssertEqualObjects(set2, expected2);
}

#pragma mark - Charset (encoding)

- (void)test_charset_encodeLatin1 {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"æ" : @"æ"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"%E6=%E6");
}

- (void)test_charset_numericEntitiesWhenNeeded {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"☺"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=%26%239786%3B");
}

- (void)test_charset_sentinelUtf8 {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.charsetSentinel = YES;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"☺"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"utf8=%E2%9C%93&a=%E2%98%BA");
}

- (void)test_charset_sentinelLatin1 {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.charset = NSISOLatin1StringEncoding;
    opts.charsetSentinel = YES;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"æ"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"utf8=%26%2310003%3B&a=%E6");
}

- (void)test_charset_customEncoderMock {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.valueEncoderBlock =
    ^NSString *(id value, NSNumber *charsetNum, NSNumber *formatNum) {
        NSString *sv = value ? [NSString stringWithFormat:@"%@", value] : @"";
        if ([sv isEqualToString:@"a"])
            return @"%61";
        if ([sv isEqualToString:@"hello"])
            return @"%68%65%6c%6c%6f";
        return sv;
    };
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"hello"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"%61=%68%65%6c%6c%6f");
}

#pragma mark - RFC 3986 vs RFC 1738 space encoding

- (void)test_spaces_default3986 {
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"b c"} options:nil error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=b%20c");
}

- (void)test_spaces_explicit3986 {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.format = QsFormatRfc3986;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"b c"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=b%20c");
}

- (void)test_spaces_rfc1738 {
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.format = QsFormatRfc1738;
    NSError *err = nil;
    NSString *s = [Qs encode:@{@"a" : @"b c"} options:opts error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(s, @"a=b+c");
}

@end
