import SwiftUI

// Select the stable property wrapper when an SDK also exports the State macro.
typealias ViewState<Value> = SwiftUI.State<Value>
