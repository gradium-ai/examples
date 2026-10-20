import AVFoundation
import RepCoachCore
import SwiftUI

/// The live front camera, mirrored like a mirror, filling the view.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

/// Draws the detected skeleton over the preview, using the same aspect-fill mapping.
struct SkeletonOverlay: View {
    let frame: PoseFrame?
    var color: Color = .green
    /// Bones drawn in red over the rest: where a form fault is.
    var alert: [(Joint, Joint)] = []

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            // Aspect-fill: scale the image to cover the view, centred, cropping the overflow.
            let imageAspect = frame.aspect
            let viewAspect = size.width / size.height
            let drawn: CGSize = viewAspect > imageAspect
                ? CGSize(width: size.width, height: size.width / imageAspect)
                : CGSize(width: size.height * imageAspect, height: size.height)
            let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            func place(_ joint: Joint) -> CGPoint? {
                guard frame.sees(joint), let p = frame.joints[joint] else { return nil }
                return CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + (1 - p.y) * drawn.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = place(a), let pb = place(b) else { continue }
                path.move(to: pa)
                path.addLine(to: pb)
            }
            context.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            var faulty = Path()
            for (a, b) in alert {
                guard let pa = place(a), let pb = place(b) else { continue }
                faulty.move(to: pa)
                faulty.addLine(to: pb)
            }
            context.stroke(faulty, with: .color(.red.opacity(0.35)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            context.stroke(faulty, with: .color(.red), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            for joint in Joint.allCases {
                guard let p = place(joint) else { continue }
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
