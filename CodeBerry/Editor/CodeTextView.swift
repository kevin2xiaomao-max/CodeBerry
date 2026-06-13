import UIKit

/// UITextView tuned for code: TextKit 1 stack (for layoutManager-based line
/// geometry), a floating line-number gutter, and no smart-text interference.
final class CodeTextView: UITextView {
    static let gutterWidth: CGFloat = 44

    private let gutter = LineNumberGutter()
    /// Character index of the start of every logical line; gutter uses it to
    /// number lines without rescanning the document per draw.
    private(set) var lineStarts: [Int] = [0]

    init() {
        // Build the TextKit 1 stack explicitly so layoutManager APIs are safe.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure() {
        backgroundColor = CodeTheme.background
        font = CodeTheme.font
        typingAttributes = CodeTheme.baseAttributes
        textContainerInset = UIEdgeInsets(top: 12, left: Self.gutterWidth + 6, bottom: 12, right: 4)
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        keyboardType = .asciiCapable
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        indicatorStyle = .default

        gutter.textView = self
        gutter.isOpaque = true
        addSubview(gutter)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTextChange),
                                               name: UITextView.textDidChangeNotification,
                                               object: self)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CodeTextView, _) in
            SwiftHighlighter.highlight(view.textStorage)
            view.gutter.setNeedsDisplay()
        }
    }

    @objc private func handleTextChange() { textDidUpdate() }

    /// Recomputes line starts and redraws the gutter. Call after programmatic
    /// text changes (the textDidChange notification only fires for user edits).
    func textDidUpdate() {
        let ns = text as NSString
        var starts: [Int] = [0]
        for i in 0..<ns.length where ns.character(at: i) == 10 {
            starts.append(i + 1)
        }
        lineStarts = starts
        gutter.setNeedsDisplay()
    }

    override var contentOffset: CGPoint {
        didSet { layoutGutter() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGutter()
    }

    private func layoutGutter() {
        // Pinned to the visible viewport (the text view scrolls its subviews).
        let frame = CGRect(x: contentOffset.x, y: contentOffset.y,
                           width: Self.gutterWidth, height: bounds.height)
        if gutter.frame != frame { gutter.frame = frame }
        gutter.setNeedsDisplay()
    }
}

/// Draws line numbers for the visible viewport only.
private final class LineNumberGutter: UIView {
    weak var textView: CodeTextView?

    override func draw(_ rect: CGRect) {
        guard let tv = textView, let ctx = UIGraphicsGetCurrentContext() else { return }

        CodeTheme.background.setFill()
        ctx.fill(bounds)
        UIColor.separator.withAlphaComponent(0.4).setFill()
        ctx.fill(CGRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height))

        let lm = tv.layoutManager
        let container = tv.textContainer
        let insetTop = tv.textContainerInset.top
        let offsetY = tv.contentOffset.y
        let ns = tv.text as NSString
        let starts = tv.lineStarts
        let attrs: [NSAttributedString.Key: Any] = [
            .font: CodeTheme.gutterFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]

        // First line that could be visible at the current scroll offset.
        let topPoint = CGPoint(x: 4, y: max(0, offsetY - insetTop))
        let topGlyph = lm.glyphIndex(for: topPoint, in: container)
        let topChar = lm.characterIndexForGlyph(at: topGlyph)
        var lineIdx = lastLineIndex(in: starts, atOrBefore: topChar)
        let maxY = offsetY + bounds.height

        while lineIdx < starts.count {
            let startChar = starts[lineIdx]
            let lineRect: CGRect
            if startChar >= ns.length {
                // Trailing empty line (or empty document): the extra fragment.
                guard ns.length == 0 || ns.character(at: ns.length - 1) == 10 else { break }
                let extra = lm.extraLineFragmentRect
                lineRect = extra.height > 0
                    ? extra
                    : CGRect(x: 0, y: extra.minY, width: 0, height: CodeTheme.font.lineHeight)
            } else {
                let glyph = lm.glyphIndexForCharacter(at: startChar)
                lineRect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let y = lineRect.minY + insetTop
            if y > maxY { break }
            let drawY = y - offsetY
            if drawY + lineRect.height >= 0 {
                let number = "\(lineIdx + 1)" as NSString
                let size = number.size(withAttributes: attrs)
                number.draw(at: CGPoint(x: bounds.width - 8 - size.width,
                                        y: drawY + (lineRect.height - size.height) / 2),
                            withAttributes: attrs)
            }
            lineIdx += 1
        }
    }

    private func lastLineIndex(in starts: [Int], atOrBefore charIndex: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= charIndex { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
