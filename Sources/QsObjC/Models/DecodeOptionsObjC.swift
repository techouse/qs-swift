#if canImport(ObjectiveC) && QS_OBJC_BRIDGE
    import Foundation
    import QsSwift

    /// Objective-C wrapper for `QsSwift.DecodeOptions`.
    ///
    /// This class is mutable and designed to be configured from Obj-C or Swift,
    /// then bridged to the Swift core via the internal `swift` computed property.
    /// It mirrors the Swift API closely, including defaults.
    ///
    /// Thread-safety: not thread-safe. Configure on one thread, then pass into a call.
    ///
    /// Obj-C usage example:
    /// ```objc
    /// QsDecodeOptions *opts = [QsDecodeOptions new];
    /// opts.ignoreQueryPrefix = YES;
    /// opts.allowDots = YES;                  // treat `a.b` as `a[b]`
    /// opts.delimiter = QsDelimiter.ampersand; // `&` (default)
    /// opts.duplicates = QsDuplicatesCombine; // combine duplicate keys
    /// NSDictionary *out = [Qs decode:@"?a=1&a=2" options:opts error:NULL];
    /// ```
    @objc(QsDecodeOptions)
    @objcMembers
    public final class DecodeOptionsObjC: NSObject, @unchecked Sendable {

        // MARK: - Custom decoders

        /// If set, called to decode a single percent-encoded scalar **before** it’s interpreted
        /// by the core. Return the decoded value (e.g. `NSString`, `NSNumber`, `NSNull`, etc.),
        /// or `nil` to produce an absent value. The core will honor `nil` (no fallback).
        ///
        /// - Parameters:
        ///   - string:  The raw token as an Objective‑C string. May be `nil` if the source is empty.
        ///   - charset: `NSNumber` wrapping `String.Encoding.rawValue`, or `nil` if unspecified.
        ///
        /// Tips:
        /// - If you enable `interpretNumericEntities`, you generally don’t need to handle HTML
        ///   entities here—the core can do that for you.
        /// - Return values are inserted verbatim into the decoded map, so ensure they are
        ///   Foundation types (NSString/NSNumber/NSArray/NSDictionary/NSNull) for best bridging.
        public typealias ValueDecoderBlock = (NSString?, NSNumber?) -> Any?
        public var valueDecoderBlock: ValueDecoderBlock?

        /// Preferred: KEY/VALUE-aware scalar decoder.
        /// Signature: token, charset (String.Encoding.rawValue), kind (0=key, 1=value) -> Any?
        public typealias DecoderBlock = (NSString?, NSNumber?, NSNumber?) -> Any?
        public var decoderBlock: DecoderBlock?

        /// Back‑compat: legacy two‑argument decoder, mirroring Swift `LegacyDecoder` (deprecated).
        /// Prefer `decoderBlock` (the KEY/VALUE‑aware 3‑argument variant).
        /// Returning `nil` produces an absent value; the core will not fall back.
        public typealias LegacyDecoderBlock = (NSString?, NSNumber?) -> Any?
        public var legacyDecoderBlock: LegacyDecoderBlock?

        // MARK: - Key syntax

        /// Accept dotted key paths (`a.b.c`) as if they were bracket paths (`a[b][c]`).
        /// This is OR'ed with `decodeDotInKeys` so either flag enables dot support.
        public var allowDots: Bool = false

        /// Deprecated spelling mirroring Swift; when `true` dots in keys are parsed as path
        /// separators. Kept for compatibility with other ports. Prefer `allowDots`.
        public var decodeDotInKeys: Bool = false

        // MARK: - List / array parsing

        /// Allow empty lists like `a[]=` to produce an empty array rather than omitting the key.
        public var allowEmptyLists: Bool = false

        /// Permit sparse arrays (e.g. `a[2]=x` without lower indices). When `false`, gaps are filled.
        public var allowSparseLists: Bool = false

        /// Maximum number of items parsed into a single list (defensive cap).
        public var listLimit: Int = 20

        /// When `true`, treat commas as element separators inside a single key (e.g. `a=b,c`).
        public var comma: Bool = false

        /// Whether to parse bracketed array syntax at all (e.g. `a[0]=x`). When `false`,
        /// everything is treated as scalars / objects.
        public var parseLists: Bool = true

        /// If `true`, enforce the exact nesting depth limit below; otherwise the core
        /// may best‑effort parse past the limit for compatibility.
        public var strictDepth: Bool = false

        /// If `true`, `a` without value is `NSNull` rather than empty string. Mirrors Swift.
        public var strictNullHandling: Bool = false

        // MARK: - Limits & safety

        /// Hard cap on nested bracket depth.
        public var depth: Int = 5

        /// Hard cap on the number of key/value pairs processed from the input.
        public var parameterLimit: Int = 1000

        /// If `true`, exceedance of `listLimit`, `depth`, or `parameterLimit` throws instead
        /// of truncating/ignoring extra data.
        public var throwOnLimitExceeded: Bool = false

        // MARK: - Charset / wire format

        /// Desired input charset. Defaults to UTF‑8.
        /// Bridged to `String.Encoding(rawValue:)` in Swift.
        public var charset: UInt = String.Encoding.utf8.rawValue

        /// Interpret the `utf8=✓` sentinel (if present) per qs conventions.
        public var charsetSentinel: Bool = false

        /// Pair delimiter for query tokens (e.g. `&` or `;`).
        /// Obj‑C: this is a reference type wrapper so it bridges cleanly.
        public var delimiter: DelimiterObjC = .ampersand

        /// How to handle duplicate keys (e.g. `a=1&a=2`) — combine vs. last‑write‑wins.
        public var duplicates: DuplicatesObjC = .combine

        /// Ignore a leading `?` in the source string (useful when decoding full URLs or query parts).
        public var ignoreQueryPrefix: Bool = false

        /// Convert `&#...;` / `&name;` numeric entities inside tokens to their Unicode scalars.
        public var interpretNumericEntities: Bool = false

        // MARK: - Bridge to Swift core

        /// Internal bridge that constructs the Swift `DecodeOptions` used by the core.
        /// We also normalize the dot‑parsing flags so **either** Obj‑C flag enables dots.
        var swift: QsSwift.DecodeOptions {
            let normalizedAllowDots = allowDots || decodeDotInKeys
            let normalizedDecodeDotInKeys = decodeDotInKeys && normalizedAllowDots
            let normalizedCharset: String.Encoding = {
                let candidate = String.Encoding(rawValue: charset)
                return (candidate == .utf8 || candidate == .isoLatin1) ? candidate : .utf8
            }()
            let normalizedParameterLimit = max(1, parameterLimit)
            let normalizedDepth = max(0, depth)

            // Bridge Obj-C decoder blocks → Swift ScalarDecoder
            // Prefer the KEY/VALUE-aware `decoderBlock`; fall back to `valueDecoderBlock`.
            let swiftDecoder: QsSwift.ScalarDecoder? = {
                if let blk = decoderBlock {
                    let box = _BlockBox(blk)
                    return { (str: String?, charset: String.Encoding?, kind: QsSwift.DecodeKind?) in
                        let csNum = charset.map { NSNumber(value: $0.rawValue) }
                        let kindNum: NSNumber =
                            {
                                switch kind ?? .value {
                                case .key: return 0
                                case .value: return 1
                                }
                            }() as NSNumber
                        return box.block(str as NSString?, csNum, kindNum)
                    }
                }
                if let blk = valueDecoderBlock {
                    let box = _BlockBox(blk)
                    return { (str: String?, charset: String.Encoding?, _: QsSwift.DecodeKind?) in
                        let csNum = charset.map { NSNumber(value: $0.rawValue) }
                        return box.block(str as NSString?, csNum)
                    }
                }
                return nil
            }()

            // Bridge legacyDecoderBlock → Swift LegacyDecoder (deprecated)
            let swiftLegacy: QsSwift.LegacyDecoder? = {
                guard let blk = legacyDecoderBlock else { return nil }
                let box = _BlockBox(blk)
                return { (str: String?, charset: String.Encoding?) in
                    let csNum = charset.map { NSNumber(value: $0.rawValue) }
                    return box.block(str as NSString?, csNum)
                }
            }()

            return QsSwift.DecodeOptions(
                // Dot handling: either flag enables it (compat with other ports).
                allowDots: normalizedAllowDots,
                decoder: swiftDecoder,
                legacyDecoder: swiftLegacy,
                decodeDotInKeys: normalizedDecodeDotInKeys,

                // Lists / arrays
                allowEmptyLists: allowEmptyLists,
                allowSparseLists: allowSparseLists,
                listLimit: listLimit,

                // Charset / wire format
                charset: normalizedCharset,
                charsetSentinel: charsetSentinel,
                comma: comma,
                delimiter: delimiter.swift,

                // Limits & behavior
                depth: normalizedDepth,
                parameterLimit: normalizedParameterLimit,
                duplicates: duplicates.swift,
                ignoreQueryPrefix: ignoreQueryPrefix,
                interpretNumericEntities: interpretNumericEntities,
                parseLists: parseLists,
                strictDepth: strictDepth,
                strictNullHandling: strictNullHandling,
                throwOnLimitExceeded: throwOnLimitExceeded
            )
        }

        // MARK: - Swift convenience

        /// Tiny Swift-only helper that lets you configure fluently:
        ///
        /// ```swift
        /// let opts = DecodeOptionsObjC().with {
        ///   $0.ignoreQueryPrefix = true
        ///   $0.allowDots = true
        /// }
        /// ```
        @discardableResult
        public func with(_ configure: (DecodeOptionsObjC) -> Void) -> Self {
            configure(self)
            return self
        }
    }
#endif
