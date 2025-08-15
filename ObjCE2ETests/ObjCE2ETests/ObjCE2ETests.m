@import XCTest;
@import QsObjC;

#import "ObjCE2ETests-Swift.h"

@interface ObjCE2ETests : XCTestCase
@end

@implementation ObjCE2ETests

- (QsEncodeOptions *)optsNoEncode {
    QsEncodeOptions *o = [[QsEncodeOptions alloc] init];
    o.encode = NO; // to match expected literal strings
    return o;
}

- (void)test_E2E_encode_decode_parametrized {
    NSMutableArray<NSDictionary *> *cases = [NSMutableArray array];
    
    // a=b&c=d&e[0]=f&e[1]=g&e[2]=h&i[j]=k&i[l]=m
    id subI = [SPMOrdered dictWithKeys:@[@"j",@"l"] values:@[@"k",@"m"]];
    id root = [SPMOrdered dictWithKeys:@[@"a",@"c",@"e",@"i"]
                                values:@[@"b",@"d", @[@"f",@"g",@"h"], subI]];
    [cases addObject:@{
        @"data": root,
        @"encoded": @"a=b&c=d&e[0]=f&e[1]=g&e[2]=h&i[j]=k&i[l]=m"
    }];
    
    // a[b]=c
    id a1 = [SPMOrdered dictWithKeys:@[@"b"] values:@[@"c"]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[a1]],
        @"encoded": @"a[b]=c"
    }];
    
    // a[0][b]=c&a[1][d]=e
    id e0 = [SPMOrdered dictWithKeys:@[@"b"] values:@[@"c"]];
    id e1 = [SPMOrdered dictWithKeys:@[@"d"] values:@[@"e"]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@[e0, e1]]],
        @"encoded": @"a[0][b]=c&a[1][d]=e"
    }];
    
    // filters[$or]… + author…
    id or0 = [SPMOrdered dictWithKeys:@[@"date"] values:@[@{@"$eq": @"2020-01-01"}]];
    id or1 = [SPMOrdered dictWithKeys:@[@"date"] values:@[@{@"$eq": @"2020-01-02"}]];
    id author = [SPMOrdered dictWithKeys:@[@"name"] values:@[@{@"$eq": @"John Doe"}]];
    id filters = [SPMOrdered dictWithKeys:@[@"$or",@"author"] values:@[@[or0,or1], author]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"filters"] values:@[filters]],
        @"encoded": @"filters[$or][0][date][$eq]=2020-01-01&filters[$or][1][date][$eq]=2020-01-02&filters[author][name][$eq]=John Doe"
    }];
    
    // commentsEmbedResponse… (full, same order as your Swift test)
    id reply0 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                                  values:@[@"3",@"1",@"ma020-9ha15",@"Hello"]];
    id post0  = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                                  values:@[@"1",@"1",@"ma018-9ha12",@"Hello", @[reply0]]];
    
    id reply10 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                                   values:@[@"4",@"2",@"mw023-9ha18",@"Hello"]];
    id reply11 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                                   values:@[@"5",@"2",@"mw035-0ha22",@"Hello"]];
    id post1  = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                                  values:@[@"2",@"1",@"mw012-7ha19",@"How are you?", @[reply10, reply11]]];
    
    id cERoot = [SPMOrdered dictWithKeys:@[@"commentsEmbedResponse"] values:@[@[post0, post1]]];
    [cases addObject:@{
        @"data": cERoot,
        @"encoded": @"commentsEmbedResponse[0][id]=1&commentsEmbedResponse[0][post_id]=1&commentsEmbedResponse[0][someId]=ma018-9ha12&commentsEmbedResponse[0][text]=Hello&commentsEmbedResponse[0][replies][0][id]=3&commentsEmbedResponse[0][replies][0][comment_id]=1&commentsEmbedResponse[0][replies][0][someId]=ma020-9ha15&commentsEmbedResponse[0][replies][0][text]=Hello&commentsEmbedResponse[1][id]=2&commentsEmbedResponse[1][post_id]=1&commentsEmbedResponse[1][someId]=mw012-7ha19&commentsEmbedResponse[1][text]=How are you?&commentsEmbedResponse[1][replies][0][id]=4&commentsEmbedResponse[1][replies][0][comment_id]=2&commentsEmbedResponse[1][replies][0][someId]=mw023-9ha18&commentsEmbedResponse[1][replies][0][text]=Hello&commentsEmbedResponse[1][replies][1][id]=5&commentsEmbedResponse[1][replies][1][comment_id]=2&commentsEmbedResponse[1][replies][1][someId]=mw035-0ha22&commentsEmbedResponse[1][replies][1][text]=Hello"
    }];
    
    
    // Run the cases
    QsEncodeOptions *opts = [self optsNoEncode];
    [cases enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull c, NSUInteger i, BOOL * _Nonnull stop) {
        id data = c[@"data"];
        NSString *expected = c[@"encoded"];
        
        NSString *got = [QsObjCTestHelpers encode:data options:opts];
        XCTAssertEqualObjects(got, expected,
                              @"encode mismatch [case %lu]\nEXPECTED: %@\nENCODED: %@",
                              (unsigned long)i, expected, got);
        
        NSDictionary *decoded = [QsObjCTestHelpers decode:expected];
        XCTAssertTrue([QsObjCTestHelpers deepEqualOrdered:data rhs:decoded],
                      @"decode mismatch [case %lu]\nENCODED: %@\nDECODED: %@",
                      (unsigned long)i, expected, decoded);
    }];
}

- (void)test_E2E_encode_decode_fullMatrix {
    QsEncodeOptions *opts = [self optsNoEncode];
    
    NSMutableArray<NSDictionary *> *cases = [NSMutableArray array];
    
    // 0) {}
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[] values:@[]],
        @"encoded": @""
    }];
    
    // 1) a=b
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@"b"]],
        @"encoded": @"a=b"
    }];
    
    // 2) a=b&c=d
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a",@"c"] values:@[@"b",@"d"]],
        @"encoded": @"a=b&c=d"
    }];
    
    // 3) a=b&c=d&e[0]=f&e[1]=g&e[2]=h
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a",@"c",@"e"]
                                   values:@[@"b",@"d", @[@"f",@"g",@"h"]]],
        @"encoded": @"a=b&c=d&e[0]=f&e[1]=g&e[2]=h"
    }];
    
    // 4) + nested dict i[j]=k&i[l]=m
    id iDict = [SPMOrdered dictWithKeys:@[@"j",@"l"] values:@[@"k",@"m"]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a",@"c",@"e",@"i"]
                                   values:@[@"b",@"d", @[@"f",@"g",@"h"], iDict]],
        @"encoded": @"a=b&c=d&e[0]=f&e[1]=g&e[2]=h&i[j]=k&i[l]=m"
    }];
    
    // 5) a[b]=c
    id b_c = [SPMOrdered dictWithKeys:@[@"b"] values:@[@"c"]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[b_c]],
        @"encoded": @"a[b]=c"
    }];
    
    // 6) a[b][c]=d
    id c_d = [SPMOrdered dictWithKeys:@[@"c"] values:@[@"d"]];
    id b_cd = [SPMOrdered dictWithKeys:@[@"b"] values:@[c_d]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[b_cd]],
        @"encoded": @"a[b][c]=d"
    }];
    
    // 7) a[0][b]=c&a[1][d]=e
    id d0 = [SPMOrdered dictWithKeys:@[@"b"] values:@[@"c"]];
    id d1 = [SPMOrdered dictWithKeys:@[@"d"] values:@[@"e"]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@[d0, d1]]],
        @"encoded": @"a[0][b]=c&a[1][d]=e"
    }];
    
    // 8) a[0]=f
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@[@"f"]]],
        @"encoded": @"a[0]=f"
    }];
    
    // 9) a[0][b][0]=c
    id deep = [SPMOrdered dictWithKeys:@[@"b"] values:@[@[@"c"]]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@[deep]]],
        @"encoded": @"a[0][b][0]=c"
    }];
    
    // 10) a=
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@""]],
        @"encoded": @"a="
    }];
    
    // 11) a[0]=&a[1]=b
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"a"] values:@[@[@"", @"b"]]],
        @"encoded": @"a[0]=&a[1]=b"
    }];
    
    // 12) Unicode keys/values
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"キー"] values:@[@"値"]],
        @"encoded": @"キー=値"
    }];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"🙂"] values:@[@"😊"]],
        @"encoded": @"🙂=😊"
    }];
    
    // 13) filters[$or]… & author…
    id or0 = [SPMOrdered dictWithKeys:@[@"date"] values:@[@{@"$eq": @"2020-01-01"}]];
    id or1 = [SPMOrdered dictWithKeys:@[@"date"] values:@[@{@"$eq": @"2020-01-02"}]];
    id author = [SPMOrdered dictWithKeys:@[@"name"] values:@[@{@"$eq": @"John Doe"}]];
    id filters = [SPMOrdered dictWithKeys:@[@"$or",@"author"] values:@[@[or0,or1], author]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"filters"] values:@[filters]],
        @"encoded": @"filters[$or][0][date][$eq]=2020-01-01&filters[$or][1][date][$eq]=2020-01-02&filters[author][name][$eq]=John Doe"
    }];
    
    // 14) commentsEmbedResponse […]
    id r0 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                              values:@[@"3",@"1",@"ma020-9ha15",@"Hello"]];
    id p0 = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                              values:@[@"1",@"1",@"ma018-9ha12",@"Hello", @[r0]]];
    
    id r10 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                               values:@[@"4",@"2",@"mw023-9ha18",@"Hello"]];
    id r11 = [SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"]
                               values:@[@"5",@"2",@"mw035-0ha22",@"Hello"]];
    id p1 = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                              values:@[@"2",@"1",@"mw012-7ha19",@"How are you?", @[r10, r11]]];
    
    id commentsEmbed = [SPMOrdered dictWithKeys:@[@"commentsEmbedResponse"] values:@[@[p0, p1]]];
    [cases addObject:@{
        @"data": commentsEmbed,
        @"encoded": @"commentsEmbedResponse[0][id]=1&commentsEmbedResponse[0][post_id]=1&commentsEmbedResponse[0][someId]=ma018-9ha12&commentsEmbedResponse[0][text]=Hello&commentsEmbedResponse[0][replies][0][id]=3&commentsEmbedResponse[0][replies][0][comment_id]=1&commentsEmbedResponse[0][replies][0][someId]=ma020-9ha15&commentsEmbedResponse[0][replies][0][text]=Hello&commentsEmbedResponse[1][id]=2&commentsEmbedResponse[1][post_id]=1&commentsEmbedResponse[1][someId]=mw012-7ha19&commentsEmbedResponse[1][text]=How are you?&commentsEmbedResponse[1][replies][0][id]=4&commentsEmbedResponse[1][replies][0][comment_id]=2&commentsEmbedResponse[1][replies][0][someId]=mw023-9ha18&commentsEmbedResponse[1][replies][0][text]=Hello&commentsEmbedResponse[1][replies][1][id]=5&commentsEmbedResponse[1][replies][1][comment_id]=2&commentsEmbedResponse[1][replies][1][someId]=mw035-0ha22&commentsEmbedResponse[1][replies][1][text]=Hello"
    }];
    
    // 15) commentsResponse […]
    id c0 = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                              values:@[@"1",@"1",@"ma018-9ha12",@"Hello", @[[SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"] values:@[@"3",@"1",@"ma020-9ha15",@"Hello"]]]]];
    id c1 = [SPMOrdered dictWithKeys:@[@"id",@"post_id",@"someId",@"text",@"replies"]
                              values:@[@"2",@"1",@"mw012-7ha19",@"How are you?", @[[SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"] values:@[@"4",@"2",@"mw023-9ha18",@"Hello"]],[SPMOrdered dictWithKeys:@[@"id",@"comment_id",@"someId",@"text"] values:@[@"5",@"2",@"mw035-0ha22",@"Hello"]]]]];
    id comments = [SPMOrdered dictWithKeys:@[@"commentsResponse"] values:@[@[c0, c1]]];
    [cases addObject:@{
        @"data": comments,
        @"encoded": @"commentsResponse[0][id]=1&commentsResponse[0][post_id]=1&commentsResponse[0][someId]=ma018-9ha12&commentsResponse[0][text]=Hello&commentsResponse[0][replies][0][id]=3&commentsResponse[0][replies][0][comment_id]=1&commentsResponse[0][replies][0][someId]=ma020-9ha15&commentsResponse[0][replies][0][text]=Hello&commentsResponse[1][id]=2&commentsResponse[1][post_id]=1&commentsResponse[1][someId]=mw012-7ha19&commentsResponse[1][text]=How are you?&commentsResponse[1][replies][0][id]=4&commentsResponse[1][replies][0][comment_id]=2&commentsResponse[1][replies][0][someId]=mw023-9ha18&commentsResponse[1][replies][0][text]=Hello&commentsResponse[1][replies][1][id]=5&commentsResponse[1][replies][1][comment_id]=2&commentsResponse[1][replies][1][someId]=mw035-0ha22&commentsResponse[1][replies][1][text]=Hello"
    }];
    
    // 16) data[…] nested object
    id user = [SPMOrdered dictWithKeys:@[@"firstname",@"lastname",@"age"] values:@[@"John",@"Doe",@"25"]];
    id tag0 = [SPMOrdered dictWithKeys:@[@"name"] values:@[@"super"]];
    id tag1 = [SPMOrdered dictWithKeys:@[@"name"] values:@[@"awesome"]];
    id tagsData = [SPMOrdered dictWithKeys:@[@"data"] values:@[@[tag0, tag1]]];
    id relationships = [SPMOrdered dictWithKeys:@[@"tags"] values:@[tagsData]];
    id dataInner = [SPMOrdered dictWithKeys:@[@"id",@"someId",@"text",@"user",@"relationships"]
                                     values:@[@"1",@"af621-4aa41",@"Lorem Ipsum Dolor", user, relationships]];
    [cases addObject:@{
        @"data": [SPMOrdered dictWithKeys:@[@"data"] values:@[dataInner]],
        @"encoded": @"data[id]=1&data[someId]=af621-4aa41&data[text]=Lorem Ipsum Dolor&data[user][firstname]=John&data[user][lastname]=Doe&data[user][age]=25&data[relationships][tags][data][0][name]=super&data[relationships][tags][data][1][name]=awesome"
    }];
    
    // 17) flat object with user & relationships
    id relationships2 = [SPMOrdered dictWithKeys:@[@"tags"] values:@[@[tag0, tag1]]];
    id flat = [SPMOrdered dictWithKeys:@[@"id",@"someId",@"text",@"user",@"relationships"]
                                values:@[@"1",@"af621-4aa41",@"Lorem Ipsum Dolor", user, relationships2]];
    [cases addObject:@{
        @"data": flat,
        @"encoded": @"id=1&someId=af621-4aa41&text=Lorem Ipsum Dolor&user[firstname]=John&user[lastname]=Doe&user[age]=25&relationships[tags][0][name]=super&relationships[tags][1][name]=awesome"
    }];
    
    // 18) postsResponse […]
    id relationshipsPR0 = [SPMOrdered dictWithKeys:@[@"tags"] values:@[@[tag0, tag1]]];
    id pR0 = [SPMOrdered dictWithKeys:@[@"id",@"someId",@"text",@"user",@"relationships"]
                               values:@[@"1",@"du761-8bc98",@"Lorem Ipsum Dolor", user, relationshipsPR0]];

    id userMary = [SPMOrdered dictWithKeys:@[@"firstname",@"lastname",@"age"] values:@[@"Mary",@"Doe",@"25"]];
    id relationshipsPR1 = [SPMOrdered dictWithKeys:@[@"tags"] values:@[@[tag0, tag1]]];
    id pR1 = [SPMOrdered dictWithKeys:@[@"id",@"someId",@"text",@"user",@"relationships"]
                               values:@[@"1",@"pa813-7jx02",@"Lorem Ipsum Dolor", userMary, relationshipsPR1]];

    id postsResponse = [SPMOrdered dictWithKeys:@[@"postsResponse"] values:@[@[pR0, pR1]]];
    [cases addObject:@{
        @"data": postsResponse,
        @"encoded": @"postsResponse[0][id]=1&postsResponse[0][someId]=du761-8bc98&postsResponse[0][text]=Lorem Ipsum Dolor&postsResponse[0][user][firstname]=John&postsResponse[0][user][lastname]=Doe&postsResponse[0][user][age]=25&postsResponse[0][relationships][tags][0][name]=super&postsResponse[0][relationships][tags][1][name]=awesome&postsResponse[1][id]=1&postsResponse[1][someId]=pa813-7jx02&postsResponse[1][text]=Lorem Ipsum Dolor&postsResponse[1][user][firstname]=Mary&postsResponse[1][user][lastname]=Doe&postsResponse[1][user][age]=25&postsResponse[1][relationships][tags][0][name]=super&postsResponse[1][relationships][tags][1][name]=awesome"
    }];
    
    // 19) posts […] & total=2
    id posts = [SPMOrdered dictWithKeys:@[@"posts",@"total"]
                                 values:@[@[pR0, pR1], @"2"]];
    [cases addObject:@{
        @"data": posts,
        @"encoded": @"posts[0][id]=1&posts[0][someId]=du761-8bc98&posts[0][text]=Lorem Ipsum Dolor&posts[0][user][firstname]=John&posts[0][user][lastname]=Doe&posts[0][user][age]=25&posts[0][relationships][tags][0][name]=super&posts[0][relationships][tags][1][name]=awesome&posts[1][id]=1&posts[1][someId]=pa813-7jx02&posts[1][text]=Lorem Ipsum Dolor&posts[1][user][firstname]=Mary&posts[1][user][lastname]=Doe&posts[1][user][age]=25&posts[1][relationships][tags][0][name]=super&posts[1][relationships][tags][1][name]=awesome&total=2"
    }];
    
    // Execute the full matrix
    [cases enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull c, NSUInteger i, BOOL * _Nonnull stop) {
        id data = c[@"data"];
        NSString *expected = c[@"encoded"];
        
        NSString *got = [QsObjCTestHelpers encode:data options:opts];
        XCTAssertEqualObjects(got, expected,
                              @"encode mismatch [case %lu]\nEXPECTED: %@\nENCODED: %@",
                              (unsigned long)i, expected, got);
        
        NSDictionary *decoded = [QsObjCTestHelpers decode:expected];
        XCTAssertTrue([QsObjCTestHelpers deepEqualOrdered:data rhs:decoded],
                      @"decode mismatch [case %lu]\nENCODED: %@\nDECODED: %@",
                      (unsigned long)i, expected, decoded);
    }];
}

@end
