@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"

@interface ObjCEncodeAsyncTests : XCTestCase
@end

@implementation ObjCEncodeAsyncTests

- (void)test_encodeAsyncOnMain_success_deliversOnMain {
    XCTestExpectation *exp = [self expectationWithDescription:@"encodeAsyncOnMain delivers on main and succeeds"];
    
    // Use a dictionary with reversed order; enable sorting so output is deterministic.
    NSDictionary *input = @{ @"b": @"2", @"a": @"1" };
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.sortKeysCaseInsensitively = YES; // ensures a=1&b=2
    
    [Qs encodeAsyncOnMain:input options:opts completion:^(__unsafe_unretained NSString * _Nullable s, NSError * _Nullable err) {
        XCTAssertTrue([NSThread isMainThread], @"Completion for encodeAsyncOnMain must run on main thread");
        XCTAssertNil(err);
        XCTAssertNotNil(s);
        XCTAssertEqualObjects(s, @"a=1&b=2");
        [exp fulfill];
    }];
    
    [self waitForExpectations:@[exp] timeout:2.0];
}

- (void)test_encodeAsync_success_deliversOffMain {
    XCTestExpectation *exp = [self expectationWithDescription:@"encodeAsync delivers off main and succeeds"];
    
    NSDictionary *input = @{ @"b": @"2", @"a": @"1" };
    QsEncodeOptions *opts = [QsEncodeOptions new];
    opts.sortKeysCaseInsensitively = YES;
    
    [Qs encodeAsync:input options:opts completion:^(__unsafe_unretained NSString * _Nullable s, NSError * _Nullable err) {
        XCTAssertFalse([NSThread isMainThread], @"Completion for encodeAsync should not run on main thread");
        XCTAssertNil(err);
        XCTAssertNotNil(s);
        XCTAssertEqualObjects(s, @"a=1&b=2");
        [exp fulfill];
    }];
    
    [self waitForExpectations:@[exp] timeout:2.0];
}

- (void)test_encodeAsync_error_cyclic_propagatesOffMain {
    XCTestExpectation *exp = [self expectationWithDescription:@"encodeAsync propagates cyclicObject error off main"];
    
    // Create a reference cycle between two dictionaries
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    NSMutableDictionary *b = [NSMutableDictionary dictionary];
    a[@"loop"] = b;
    b[@"loop"] = a;
    
    [Qs encodeAsync:a options:nil completion:^(__unsafe_unretained NSString * _Nullable s, NSError * _Nullable err) {
        XCTAssertFalse([NSThread isMainThread]);
        XCTAssertNil(s);
        XCTAssertNotNil(err);
        XCTAssertTrue([QsEncodeError isCyclicObject:err]);
        XCTAssertEqualObjects(err.domain, QsEncodeErrorInfo.domain);
        [exp fulfill];
    }];
    
    [self waitForExpectations:@[exp] timeout:2.0];
}

- (void)test_encodeAsyncOnMain_error_cyclic_propagatesOnMain {
    XCTestExpectation *exp = [self expectationWithDescription:@"encodeAsyncOnMain propagates cyclicObject error on main"];
    
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    NSMutableDictionary *b = [NSMutableDictionary dictionary];
    a[@"self"] = b;
    b[@"self"] = a;
    
    [Qs encodeAsyncOnMain:a options:nil completion:^(__unsafe_unretained NSString * _Nullable s, NSError * _Nullable err) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertNil(s);
        XCTAssertNotNil(err);
        XCTAssertTrue([QsEncodeError isCyclicObject:err]);
        XCTAssertEqualObjects(err.domain, QsEncodeErrorInfo.domain);
        [exp fulfill];
    }];
    
    [self waitForExpectations:@[exp] timeout:2.0];
}

@end
