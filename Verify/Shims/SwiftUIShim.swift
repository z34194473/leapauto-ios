import Foundation
public typealias URL2 = Foundation.URL
// ============================================================
//  SwiftUI 最小桩（仅用于在非 Apple 平台做语法/类型检查）
//  不是完整实现，只提供签名让编译器验证调用点类型正确
// ============================================================

import Foundation

// ---- 基础协议
@MainActor
public protocol View {
    associatedtype Body: View
    @MainActor @ViewBuilder var body: Body { get }
}

public protocol ButtonStyle {
    associatedtype Body: View
    func makeBody(configuration: Configuration) -> Body
}

extension ButtonStyle {
    public typealias Configuration = ButtonStyleConfiguration
}

public struct ButtonStyleConfiguration {
    public struct Label: View {
        public var body: Never { fatalError() }
        public init() {}
    }
    public let label: Label
    public let isPressed: Bool
    public let role: ButtonRole?
    nonisolated public init() {
        self.label = Label(); self.isPressed = false; self.role = nil
    }
}

public enum ButtonRole { case destructive, cancel }

public struct PlainButtonStyle: ButtonStyle {
    public typealias Body = EmptyView
    public func makeBody(configuration: ButtonStyleConfiguration) -> EmptyView { EmptyView() }
}

public struct DefaultButtonStyle: ButtonStyle {
    public typealias Body = EmptyView
    public func makeBody(configuration: ButtonStyleConfiguration) -> EmptyView { EmptyView() }
}

extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}
extension ButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
    public static var bordered: DefaultButtonStyle { DefaultButtonStyle() }
    public static var borderless: DefaultButtonStyle { DefaultButtonStyle() }
    public static var borderedProminent: DefaultButtonStyle { DefaultButtonStyle() }
}
public protocol ViewModifier {}

// ---- EmptyView / TupleView
public struct EmptyView: View {
    nonisolated public init() {}
    public var body: Never { fatalError() }
}

extension Optional: View where Wrapped: View {
    public var body: Never { fatalError() }
}
extension Never: View {
    public var body: Never { fatalError() }
}

@resultBuilder
@MainActor
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> Tuple2<C0, C1> {
        Tuple2(c0, c1)
    }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> Tuple3<C0, C1, C2> {
        Tuple3(c0, c1, c2)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> Tuple4<C0, C1, C2, C3> {
        Tuple4(c0, c1, c2, c3)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> Tuple5<C0, C1, C2, C3, C4> {
        Tuple5(c0, c1, c2, c3, c4)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> Tuple6<C0, C1, C2, C3, C4, C5> {
        Tuple6(c0, c1, c2, c3, c4, c5)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> Tuple7<C0, C1, C2, C3, C4, C5, C6> {
        Tuple7(c0, c1, c2, c3, c4, c5, c6)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7)
        -> Tuple8<C0, C1, C2, C3, C4, C5, C6, C7> {
        Tuple8(c0, c1, c2, c3, c4, c5, c6, c7)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View,
                                 C6: View, C7: View, C8: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8)
        -> Tuple9<C0, C1, C2, C3, C4, C5, C6, C7, C8> {
        Tuple9(c0, c1, c2, c3, c4, c5, c6, c7, c8)
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View,
                                 C6: View, C7: View, C8: View, C9: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9)
        -> Tuple10<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9> {
        Tuple10(c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)
    }
    public static func buildIf<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<A: View, B: View>(first: A) -> Either<A, B> { .a(first) }
    public static func buildEither<A: View, B: View>(second: B) -> Either<A, B> { .b(second) }
    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> C { c }
}

public enum Either<A: View, B: View>: View {
    case a(A), b(B)
    public var body: Never { fatalError() }
}

public struct Tuple2<A: View, B: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B) {} }
public struct Tuple3<A: View, B: View, C: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C) {} }
public struct Tuple4<A: View, B: View, C: View, D: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D) {} }
public struct Tuple5<A: View, B: View, C: View, D: View, E: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) {} }
public struct Tuple6<A: View, B: View, C: View, D: View, E: View, F: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) {} }
public struct Tuple7<A: View, B: View, C: View, D: View, E: View, F: View, G: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) {} }
public struct Tuple8<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) {} }
public struct Tuple9<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View, I: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) {} }
public struct Tuple10<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View, I: View, J: View>: View { public var body: Never { fatalError() }
    init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) {} }

// ---- 环境
final class Box<T> {
    var value: T
    init(_ v: T) { value = v }
}

@propertyWrapper
public struct State<Value> {
    private let box: Box<Value>
    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    nonisolated public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}

@propertyWrapper
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }
    nonisolated public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getter = get; self.setter = set
    }
    nonisolated public init(get: @escaping () -> Value) {
        self.getter = get; self.setter = { _ in }
    }
    public static func constant(_ v: Value) -> Binding<Value> { Binding(get: { v }, set: { _ in }) }
}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    private let box: Box<ObjectType?>
    private let factory: () -> ObjectType
    public var wrappedValue: ObjectType {
        if let s = box.value { return s }
        let o = factory(); box.value = o; return o
    }
    nonisolated public init(wrappedValue: @autoclosure @escaping () -> ObjectType) {
        self.factory = wrappedValue
        self.box = Box(nil)
    }
}

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType
    nonisolated public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
}

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType
    public var projectedValue: Wrapper { Wrapper(root: wrappedValue) }

    @dynamicMemberLookup
    public struct Wrapper {
        let root: ObjectType
        public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
            Binding(get: { self.root[keyPath: keyPath] },
                    set: { newValue in self.root[keyPath: keyPath] = newValue })
        }
    }
    nonisolated public init() { self.wrappedValue = unsafeBitCast(ObjectType.self, to: ObjectType.self) }
}

@propertyWrapper
public struct Environment<Value> {
    public var wrappedValue: Value { fatalError() }
    nonisolated public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {}
}

public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
    public var colorScheme: ColorScheme { .dark }
}

public struct DismissAction { public func callAsFunction() {} }

public enum ColorScheme { case light, dark }



// ---- 基础类型
public struct Color: Hashable, ShapeStyle {
    nonisolated public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    nonisolated public init(_ name: String) {}
    nonisolated public init(white: Double) {}
    public static let white = Color(white: 1)
    public static let black = Color(white: 0)
    public static let clear = Color(white: 0)
    public static let red = Color("red")
    public static let green = Color("green")
    public static let blue = Color("blue")
    public static let orange = Color("orange")
    public static let yellow = Color("yellow")
    public static let gray = Color("gray")
    public static let primary = Color("primary")
    public static let secondary = Color("secondary")
    public static let accentColor = Color("accent")
    public func opacity(_ v: Double) -> Color { self }
    public func ignoresSafeArea() -> Color { self }
}

public struct Font {
    public enum Weight { case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black }
    public enum Design { case `default`, serif, rounded, monospaced }
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font { Font() }
    public static func body(_: Font?) -> Font { Font() }
    public static func caption(_: Font?) -> Font { Font() }
    public static func headline(_: Font?) -> Font { Font() }
    public static func subheadline(_: Font?) -> Font { Font() }
    public static func title(_: Font?) -> Font { Font() }
    public static func footnote(_: Font?) -> Font { Font() }
    public static func largeTitle(_: Font?) -> Font { Font() }
    public func weight(_ w: Weight) -> Font { self }
    public func bold() -> Font { self }
    public func monospacedDigit() -> Font { self }
}

public struct Image: View {
    public var body: Never { fatalError() }
    nonisolated public init(systemName: String) {}
    nonisolated public init(_ name: String) {}
    nonisolated public init(uiImage: Any) {}
    public func resizable() -> Image { self }
    public func scaledToFit() -> Image { self }
    public func aspectRatio(_ r: CGFloat?, contentMode: ContentMode) -> Image { self }
    public enum ContentMode { case fit, fill }
}

public struct Text: View {
    public enum TruncationMode { case head, middle, tail }
    public var body: Never { fatalError() }
    nonisolated public init(_ s: String) {}
    nonisolated public init(_ s: String, tableName: String? = nil) {}
    public func font(_ f: Font?) -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { self }
    public func foregroundStyle<S>(_ s: S) -> Text { self }
    public func bold() -> Text { self }
    public func lineLimit(_ n: Int?) -> Text { self }
    public func minimumScaleFactor(_ f: CGFloat) -> Text { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> Text { self }
}

public enum TextAlignment { case leading, center, trailing }

public struct Label: View {
    public var body: Never { fatalError() }
    nonisolated public init(_ title: String, systemImage: String) {}
    nonisolated public init(_ title: String, image: String) {}
}

public struct VStack<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct HStack<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct ZStack<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}

public enum HorizontalAlignment { case leading, center, trailing }
public struct VerticalAlignment: Hashable, Sendable {
    public static let top = VerticalAlignment()
    public static let center = VerticalAlignment()
    public static let bottom = VerticalAlignment()
    public static let firstTextBaseline = VerticalAlignment()
    public static let lastTextBaseline = VerticalAlignment()
    public init() {}
}
public struct Alignment { public static let center = Alignment(); public static let leading = Alignment(); public static let top = Alignment() }

public struct Spacer: View {
    public var body: Never { fatalError() }
    nonisolated public init(minLength: CGFloat? = nil) {}
}

public struct Divider: View {
    public var body: Never { fatalError() }
    nonisolated public init() {}
}

public struct ScrollView<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {}
}

public enum Axis: Sendable {
    public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let vertical = Set(rawValue: 1); public static let horizontal = Set(rawValue: 2) }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data.Element: Identifiable, ID == Data.Element.ID {}
    nonisolated public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

public struct List<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, Data.Element.ID>, @ViewBuilder row: @escaping (Data.Element) -> RowContent) where Data.Element: Identifiable {}
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, @ViewBuilder row: @escaping (Data.Element) -> RowContent) where Data.Element: Identifiable {}
}

public struct NavigationStack<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
}

public struct NavigationLink<Label: View, Destination: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {}
}

public struct Form<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
}

public struct Section<Content: View, Header: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
    nonisolated public init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text {}
}

public struct Button<Label: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
}

extension Button where Label == Text {
    nonisolated public init(_ title: String, action: @escaping () -> Void) {}
    nonisolated public init(_ title: String, systemImage: String, action: @escaping () -> Void) {}
}

public struct Toggle<Label: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {}
}

extension Toggle where Label == Text {
    nonisolated public init(_ title: String, isOn: Binding<Bool>) {}
}

public struct TextField<Label: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(_ title: String, text: Binding<String>) {}
    nonisolated public init(_ title: String, text: Binding<String>, onCommit: @escaping () -> Void) {}
}

extension TextField where Label == Text {
    nonisolated public init(_ title: String, text: Binding<String>) {}
}

public struct SecureField<Label: View>: View {
    public var body: Never { fatalError() }
}

extension SecureField where Label == Text {
    nonisolated public init(_ title: String, text: Binding<String>) {}
}

public struct TextEditor: View {
    public var body: Never { fatalError() }
    nonisolated public init(text: Binding<String>) {}
}

public struct ProgressView: View {
    public var body: Never { fatalError() }
    nonisolated public init() {}
    public func scaleEffect(_ s: CGFloat) -> ProgressView { self }
}

public struct Image2: View { public var body: Never { fatalError() } }

public struct LazyVGrid<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(columns: [GridItem], alignment: HorizontalAlignment = .center,
                spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(),
                @ViewBuilder content: () -> Content) {}
}

public struct GridItem {
    public enum Size { case fixed(CGFloat), flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity), adaptive(minimum: CGFloat, maximum: CGFloat = .infinity) }
    nonisolated public init(_ size: Size, spacing: CGFloat? = nil, alignment: Alignment? = nil) {}
    public static func flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity) -> GridItem { GridItem(.flexible(minimum: minimum, maximum: maximum)) }
}

public struct PinnedScrollableViews: OptionSet {
    public let rawValue: Int
    nonisolated public init(rawValue: Int = 0) { self.rawValue = rawValue }
}

public struct NavigationTitle: View { public var body: Never { fatalError() } }

// ---- 修饰符（全部返回自身类型，用于语法检查）
extension View {
    public func padding(_ v: CGFloat) -> Self { self }
    public func padding(_ edges: Edge.Set = .all, _ v: CGFloat? = nil) -> Self { self }
    public func padding(_ insets: EdgeInsets) -> Self { self }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> Self { self }
    public func frame(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> Self { self }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> Self { self }
    public func background<S: View>(@ViewBuilder _ v: () -> S) -> Self { self }
    public func background<S: ShapeStyle>(_ s: S, in shape: S2) -> Self { self }
    public func overlay<S: View>(@ViewBuilder _ v: () -> S, alignment: Alignment = .center) -> Self { self }
    public func overlay<V: View>(_ v: V, alignment: Alignment = .center) -> Self { self }
    public func background<V: View>(_ v: V, alignment: Alignment = .center) -> Self { self }
    public func foregroundColor(_ c: Color?) -> Self { self }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> Self { self }
    public func font(_ f: Font?) -> Self { self }
    public func bold() -> Self { self }
    public func opacity(_ v: Double) -> Self { self }
    public func cornerRadius(_ r: CGFloat, antialiased: Bool = true) -> Self { self }
    public func shadow(color: Color = Color(white: 0), radius: CGFloat = 0, x: CGFloat = 0, y: CGFloat = 0) -> Self { self }
    public func shadow(_ s: Shadow) -> Self { self }
    public func lineLimit(_ n: Int?) -> Self { self }
    public func minimumScaleFactor(_ f: CGFloat) -> Self { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> Self { self }
    public func fixedSize(horizontal: Bool = false, vertical: Bool = false) -> Self { self }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> Self { self }
    public func rotationEffect(_ a: Angle, anchor: UnitPoint = .center) -> Self { self }
    public func animation<V: Equatable>(_ a: Animation?, value: V) -> Self { self }
    public func transition(_ t: AnyTransition) -> Self { self }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> Self { self }
    public func onAppear(perform: (() -> Void)? = nil) -> Self { self }
    public func onDisappear(perform: (() -> Void)? = nil) -> Self { self }
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> Self { self }
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> Self { self }
    public func sheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> Self { self }
    public func fullScreenCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> Self { self }
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> Self { self }
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> Self { self }
    public func refreshable(action: @escaping () async -> Void) -> Self { self }
    public func tabItem<Label: View>(@ViewBuilder label: () -> Label) -> Self { self }
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> Self { self }
    public func navigationTitle(_ title: String) -> Self { self }
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> Self { self }
    public func presentationBackground<V: View>(_ v: V) -> Self { self }
    public func presentationDetents(_ d: Set<PresentationDetent>) -> Self { self }
    public func tint(_ c: Color?) -> Self { self }
    public func background(_ c: Color) -> Self { self }
    public func keyboardType(_ t: UIKeyboardType) -> Self { self }
    public func textInputAutocapitalization(_ s: TextInputAutocapitalization?) -> Self { self }
    public func autocorrectionDisabled(_ disable: Bool = true) -> Self { self }
    public func scrollContentBackground(_ v: Visibility) -> Self { self }
    public func listRowBackground<V: View>(_ v: V?) -> Self { self }
    public func buttonStyle<S: ButtonStyle>(_ s: S) -> Self { self }
    public func disabled(_ d: Bool) -> Self { self }
    public func hidden() -> Self { self }
    public func labelsHidden() -> Self { self }
    public func environmentObject<T: ObservableObject>(_ o: T) -> Self { self }
    public func preferredColorScheme(_ s: ColorScheme?) -> Self { self }
    public func accentColor(_ c: Color?) -> Self { self }
    public func lineSpacing(_ v: CGFloat) -> Self { self }
    public func truncationMode(_ m: Text.TruncationMode) -> Self { self }
    public func clipped() -> Self { self }
    public func contentShape<S: Shape>(_ s: S) -> Self { self }
}

public typealias S2 = AnyShapeStyle
public protocol ShapeStyle {}

public struct AnyShapeStyle: ShapeStyle { public init<S: ShapeStyle>(_ s: S) {} }
public struct Shadow { }
public struct EdgeInsets { }
public struct UnitPoint { public static let center = UnitPoint() }
public struct Angle { public static func degrees(_ d: Double) -> Angle { Angle() } }
public struct Animation {
    public static let easeInOut: Animation = Animation()
    public static let easeOut: Animation = Animation()
    public static let easeIn: Animation = Animation()
    public static let linear: Animation = Animation()
    public static var `default`: Animation { Animation() }
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func easeIn(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static func spring(duration: Double) -> Animation { Animation() }
}
public func withAnimation<Result>(_ animation: Animation? = .default,
                                   _ body: () throws -> Result) rethrows -> Result { try body() }

public struct AnyTransition { public static let opacity = AnyTransition()
    public func combined<T: Transition>(with t: T) -> AnyTransition { self }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() } }
public protocol Transition {}
public enum Edge { case top, bottom, leading, trailing
    public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let all = Set(rawValue: 1); public static let top = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4); public static let leading = Set(rawValue: 8)
        public static let trailing = Set(rawValue: 16); public static let horizontal = Set(rawValue: 32)
        public static let vertical = Set(rawValue: 64) } }
public struct SafeAreaRegions: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
    public static let all = SafeAreaRegions(rawValue: 1) }
public enum Visibility { case automatic, visible, hidden }
public struct TextInputAutocapitalization { public static let never = TextInputAutocapitalization() }
public struct PresentationDetent: Hashable { }
public struct TaskPriority: Sendable { public static let userInitiated = TaskPriority() }
public struct ToolbarItemGroup<Content: View>: ToolbarContent { public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {} }
public protocol ToolbarContent {}
public struct ToolbarItem<Content: View>: ToolbarContent {
    nonisolated public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {}
}
public struct ToolbarItemPlacement {
    public static let navigationBarLeading = ToolbarItemPlacement()
    public static let navigationBarTrailing = ToolbarItemPlacement()
    public static let automatic = ToolbarItemPlacement()
    public static let principal = ToolbarItemPlacement()
}
@resultBuilder
@MainActor
public struct ToolbarContentBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(_ c0: C0, _ c1: C1) -> Tuple2T<C0, C1> { Tuple2T() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> Tuple3T<C0, C1, C2> { Tuple3T() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> Tuple4T<C0, C1, C2, C3> { Tuple4T() }
    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
}
public struct Tuple2T<A: ToolbarContent, B: ToolbarContent>: ToolbarContent {}
public struct Tuple3T<A: ToolbarContent, B: ToolbarContent, C: ToolbarContent>: ToolbarContent {}
public struct Tuple4T<A: ToolbarContent, B: ToolbarContent, C: ToolbarContent, D: ToolbarContent>: ToolbarContent {}

public enum NavigationBarItem {
    public enum TitleDisplayMode { case automatic, inline, large }
}

// ---- Shape / Path
public protocol Shape: View {}
public struct RoundedRectangle: Shape {
    public var body: Never { fatalError() }
    public struct CornerRadius { }
    public enum Style { case circular, continuous }
    nonisolated public init(cornerRadius: CGFloat, style: Style = .circular) {}
}
public struct Rectangle: Shape { public var body: Never { fatalError() }; public init() {} }
public struct Circle: Shape { public var body: Never { fatalError() }; public init() {} }
public struct Capsule: Shape { public var body: Never { fatalError() }; public init() {} }
public struct Path { }

public struct StrokeView<S: Shape>: View {
    public var body: Never { fatalError() }
}

extension Shape {
    public func fill<S: ShapeStyle>(_ s: S) -> some View { EmptyView() }
    public func stroke<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> some View { EmptyView() }
    public func stroke<S: ShapeStyle>(_ s: S, style: StrokeStyle) -> some View { EmptyView() }
    public func stroke(lineWidth: CGFloat = 1) -> some View { EmptyView() }
    public func trim(from: CGFloat, to: CGFloat) -> Self { self }
}

public struct StrokeStyle { public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {} }
public enum CGLineCap { case butt, round, square }
public enum CGLineJoin { case miter, round, bevel }
public struct LinearGradient: ShapeStyle {
    nonisolated public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {}
    nonisolated public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {}
}
public struct AngularGradient: ShapeStyle { public init(colors: [Color], center: UnitPoint) {} }
public struct Gradient { }
public struct RadialGradient: ShapeStyle { public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {} }

// ---- GeometryReader
public struct GeometryReader<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
}
public struct GeometryProxy {
    public var size: CGSize { CGSize(width: 0, height: 0) }
}
public struct CGSize { public var width: CGFloat; public var height: CGFloat }

// ---- App / Scene
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
    init()
}
@resultBuilder
@MainActor
public struct SceneBuilder {
    public static func buildBlock<C: Scene>(_ c: C) -> C { c }
}
public protocol Scene {}
public struct WindowGroup<Content: View>: Scene {
    nonisolated public init(@ViewBuilder content: () -> Content) {}
}

// ---- TabView
public struct TabView<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
    
}

// ---- 其他
public struct Group<Content: View>: View {
    public var body: Never { fatalError() }
    nonisolated public init(@ViewBuilder content: () -> Content) {}
}
public struct AnyView: View {
    public var body: Never { fatalError() }
    public init<V: View>(_ v: V) {}
}
public struct DynamicView: View { public var body: Never { fatalError() } }

// UIKit 桩
public enum UIKeyboardType { case `default`, numberPad, decimalPad, asciiCapable, emailAddress, phonePad }
public enum UIUserInterfaceStyle { case unspecified, light, dark }
public final class UIColor {
    nonisolated public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public convenience init(_ c: Color) { self.init(red: 0, green: 0, blue: 0, alpha: 1) }
    public static let white = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
}
public final class UIImage {
    public init?(data: Data) {}
    public init?(named: String) {}
}
public final class UIPasteboard {
    public static let general = UIPasteboard()
    public var string: String?
}
public final class UINavigationBarAppearance {
    nonisolated public init() {}
    public func configureWithOpaqueBackground() {}
    public var backgroundColor: UIColor?
    public var titleTextAttributes: [NSAttributedString.Key: Any]?
    public var largeTitleTextAttributes: [NSAttributedString.Key: Any]?
}
public final class UITabBarAppearance {
    nonisolated public init() {}
    public func configureWithOpaqueBackground() {}
    public var backgroundColor: UIColor?
}
public final class UINavigationBar {
    public static let appearance = UINavigationBarAppearanceHolder()
}
public final class UINavigationBarAppearanceHolder {
    public var standardAppearance: UINavigationBarAppearance?
    public var scrollEdgeAppearance: UINavigationBarAppearance?
    public var compactAppearance: UINavigationBarAppearance?
}
public final class UITabBar {
    public static let appearance = UITabBarAppearanceHolder()
}
public final class UITabBarAppearanceHolder {
    public var standardAppearance: UITabBarAppearance?
    public var scrollEdgeAppearance: UITabBarAppearance?
}

// ---- CGFloat

// ---- 补充常见命名
public struct Text2 { }

extension EnvironmentValues { }

import Combine


extension Color: View {
    public var body: Never { fatalError() }
}
