import SwiftUI

#if os(iOS)
extension View {
    /// The keyboard for a field that takes a number: `type`, the number or
    /// decimal pad, on an iPhone, and the full keyboard's numbers and
    /// punctuation on an iPad.
    ///
    /// Since iPadOS 26 the number and decimal pads are a small pad that
    /// floats beside the field. On an iPad, typing an amount in the tour and
    /// tapping the next field stopped the app: UIKit threw an
    /// `NSLayoutConstraint` exception while it laid out its own keyboard
    /// window (`UIInputWindowControllerHostingItem`), with none of the app's
    /// code on the stack. Others report the same exception with that pad and
    /// a floating or minimized keyboard, as with a hardware keyboard attached.
    func numberKeyboard(_ type: UIKeyboardType) -> some View {
        keyboardType(UIDevice.current.userInterfaceIdiom == .pad ? .numbersAndPunctuation : type)
    }
}
#endif
