# Linux support status (QsSwift)

**TL;DR:** QsSwift currently **does not support Linux**. The blocker isn’t the Objective‑C bridge (it’s fully gated out on non‑Apple platforms), but the lack of **CoreFoundation/Objective‑C runtime facilities in Swift Foundation on Linux**—most notably `NSMapTable`, which the encoder uses for **weak, identity‑based cycle detection**. See the Swift forums discussion *“Formalizing the unavailability of Core Foundation”* for background: https://forums.swift.org/t/formalizing-the-unavailability-of-core-foundation/40216

---

## What fails on Linux

- The **encoder** relies on `NSMapTable<AnyObject, AnyObject>.weakToWeakObjects()` as a **side‑channel** to detect reference cycles as it recursively walks nested graphs.
- On Linux, Swift’s Foundation **does not ship** `NSMapTable` (and related CF types). As a result, the Linux build can’t compile the encoder codepath that depends on it.
- Some **tests** also use CoreFoundation helpers (e.g. `CFNumberIsFloatType`) which are similarly unavailable on Linux.

> Note: The Objective‑C shim in `Sources/QsObjC` is wrapped with:
>
> ```swift
> #if canImport(ObjectiveC) && QS_OBJC_BRIDGE
> // … ObjC bridge …
> #endif
> ```
>
> so it is **not** compiled on Linux. The bridge is **not** the blocker.

---

## Why the encoder uses `NSMapTable`

The stringifier needs to:
1. Perform **cycle detection** across arbitrarily nested containers.
2. Preserve **identity semantics** (i.e., the same instance visited again in the recursion should be recognized).
3. Avoid retaining everything it sees just to detect cycles.

`NSMapTable` gives us a **weak‑to‑weak identity map** that is perfect for this job: it lets us thread a lightweight side‑channel through recursive calls without creating retain cycles or changing lifetimes of user objects.

There is currently no **standard library** equivalent on Linux that provides a weak, identity‑keyed map for `AnyObject`.

---

## Why we don’t ship a fallback (for now)

We evaluated a few alternatives and rejected them for correctness/behavior reasons:

- **Strong `ObjectIdentifier` → strong dictionary:** changes object lifetimes and can hide real cycles (memory blow‑ups on large graphs).
- **Manual weak wrappers / `Unmanaged` tricks:** easy to get subtly wrong across generics/`AnyObject`, and still not a drop‑in for `NSMapTable` semantics.
- **Disable cycle detection on Linux:** would diverge from behavior on Apple platforms (silent infinite recursion or late crashes).

Until we have a robust, zero‑leak, identity‑preserving weak map on Linux, we prefer to **fail early** rather than ship differing semantics.

---

## What would be needed for Linux support

Any of the following would unblock us:

1. A cross‑platform **weak identity map** abstraction (e.g., a new type in Swift Foundation/Collections).
2. A portable shim crate we can depend on that provides `NSMapTable`‑like behavior.
3. A re‑architecture of cycle detection that does not rely on weak identity maps (without sacrificing semantics).

If you’re interested in contributing any of the above, please open an issue or a PR to discuss the design.

---

## Current alternatives

If you need a production‑ready implementation today on Linux, consider the original Node.js [qs](https://www.npmjs.com/package/qs) library or any of these maintained ports:

- **Python**: [qs_codec](https://pypi.org/project/qs-codec/)
- **Kotlin/JVM**: [qs-kotlin](https://central.sonatype.com/artifact/io.github.techouse/qs-kotlin)
- **Dart**: [qs_dart](https://pub.dev/packages/qs_dart)
- **C#/.NET**: [QsNet](https://www.nuget.org/packages/QsNet)

The Node.js `qs` package is the original reference implementation; the other ports — including this Swift version — aim for feature parity and consistent edge‑case handling with it. If you spot a divergence, please open an issue in the relevant repo.

---

## FAQ

**Is the Objective‑C bridge the problem?**
No. The ObjC bridge is entirely behind `#if canImport(ObjectiveC) && QS_OBJC_BRIDGE` and is **not compiled** on Linux.

**What specific API is missing?**
Primarily `NSMapTable` (and related CoreFoundation helpers used in tests like `CFNumberIsFloatType`).

**Does decoding work on Linux?**
We don’t ship partial builds; at present the package is “Apple‑only” to keep behavior consistent across platforms.

---

## Status & tracking

Linux support is tracked in the project issue tracker. Contributions are welcome—especially portable weak‑map abstractions or designs that preserve encoder semantics without CoreFoundation.

---

## Contact

- Repository: https://github.com/techouse/qs-swift
- If you plan to work on Linux support, please open an issue to discuss approach and constraints before starting a PR.
