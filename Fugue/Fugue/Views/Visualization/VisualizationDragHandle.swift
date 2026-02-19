import SwiftUI

struct VisualizationDragHandle: View {
    @Binding var height: Double
    @State private var dragStartHeight: Double?

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = height
                        }
                        // Dragging up increases height, dragging down decreases
                        height = max(100, min(500, (dragStartHeight ?? height) - value.translation.height))
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
    }
}
