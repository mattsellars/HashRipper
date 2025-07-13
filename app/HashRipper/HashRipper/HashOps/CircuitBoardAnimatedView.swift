import SwiftUI

struct CircuitBoardLoopingView: View {
    let spacing: CGFloat = 12
    let traceCount = 100
    let traceLength = 600
    let loopDuration: TimeInterval = 60

    struct Segment {
        let start: CGPoint
        let end: CGPoint
        let delay: TimeInterval
    }

    func generateTraces(size: CGSize) -> [Segment] {
        let cols = Int(size.width / spacing)
        let rows = Int(size.height / spacing)

        var segments: [Segment] = []

        for _ in 0..<traceCount {
            var currentCol = Int.random(in: 0..<cols)
            var currentRow = Int.random(in: 0..<rows)

            var trace: [Segment] = []
            var delay = Double.random(in: 0..<loopDuration)

            for _ in 0..<traceLength {
                let horizontal = Bool.random()
                let delta = Bool.random() ? 1 : -1

                var nextCol = currentCol
                var nextRow = currentRow

                if horizontal {
                    nextCol += delta
                } else {
                    nextRow += delta
                }

                guard nextCol >= 0 && nextCol < cols,
                      nextRow >= 0 && nextRow < rows else { continue }

                let start = CGPoint(x: CGFloat(currentCol) * spacing, y: CGFloat(currentRow) * spacing)
                let end = CGPoint(x: CGFloat(nextCol) * spacing, y: CGFloat(nextRow) * spacing)
                trace.append(Segment(start: start, end: end, delay: delay))
                delay += 0.1
                currentCol = nextCol
                currentRow = nextRow
            }

            segments.append(contentsOf: trace)
        }

        return segments
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let segments = generateTraces(size: size)

            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loopDuration)

                Canvas { context, _ in
                    for segment in segments {
                        let progress = time - segment.delay
                        if progress < 0 || progress > 1 { continue }

                        let t = min(progress / 0.5, 1.0)
                        let dx = segment.end.x - segment.start.x
                        let dy = segment.end.y - segment.start.y

                        let currentPoint = CGPoint(
                            x: segment.start.x + dx * t,
                            y: segment.start.y + dy * t
                        )

                        var path = Path()
                        path.move(to: segment.start)
                        path.addLine(to: currentPoint)

                        context.stroke(path, with: .color(.orange), lineWidth: 1)
                    }
                }
            }
            .background(Color.black.opacity(0.6))
        }
    }
}

fileprivate struct ContentView: View {
    var body: some View {
        CircuitBoardLoopingView()
            .ignoresSafeArea()
    }
}
