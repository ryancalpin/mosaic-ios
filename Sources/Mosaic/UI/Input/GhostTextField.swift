import SwiftUI
import UIKit

struct GhostTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "command"
    var fontSize: CGFloat = 14
    var ghostSuffix: String?
    var onAcceptGhost: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GhostUITextField {
        let field = GhostUITextField()
        field.delegate = context.coordinator
        field.font = UIFont(name: "JetBrains Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = UIColor(Color.mosaicTextPri)
        field.tintColor = UIColor(Color.mosaicAccent)
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .send
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .font: UIFont(name: "JetBrains Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: UIColor(Color.mosaicTextSec.opacity(0.5))
        ])
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: GhostUITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }
        uiView.ghostSuffix = ghostSuffix
        uiView.font = UIFont(name: "JetBrains Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.updateGhostLayer()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GhostTextField
        init(_ parent: GhostTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) { parent.text = sender.text ?? "" }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.onSubmit?(); return false }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string == "\t" { parent.onAcceptGhost?(); return false }
            return true
        }
    }
}

final class GhostUITextField: UITextField {
    var ghostSuffix: String? { didSet { updateGhostLayer() } }
    private let ghostLayer = CATextLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ghostLayer.isWrapped = false
        ghostLayer.truncationMode = .end
        ghostLayer.foregroundColor = UIColor(Color.mosaicTextSec).withAlphaComponent(0.45).cgColor
        layer.addSublayer(ghostLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateGhostLayer() {
        guard let suffix = ghostSuffix, !suffix.isEmpty else { ghostLayer.string = nil; ghostLayer.isHidden = true; return }
        ghostLayer.isHidden = false
        ghostLayer.contentsScale = window?.windowScene?.screen.scale ?? 2.0
        let font = self.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        ghostLayer.font = ctFont; ghostLayer.fontSize = font.pointSize; ghostLayer.string = suffix
        setNeedsLayout(); layoutIfNeeded()
        let caretRect = caretRect(for: endOfDocument)
        let layerHeight = font.lineHeight + 2
        ghostLayer.frame = CGRect(x: caretRect.minX, y: (bounds.height - layerHeight) / 2, width: bounds.width - caretRect.minX, height: layerHeight)
    }

    override func layoutSubviews() { super.layoutSubviews(); updateGhostLayer() }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(acceptGhost))]
    }

    @objc private func acceptGhost() {
        guard let suffix = ghostSuffix, !suffix.isEmpty else { return }
        text = (text ?? "") + suffix
        sendActions(for: .editingChanged)
    }
}
