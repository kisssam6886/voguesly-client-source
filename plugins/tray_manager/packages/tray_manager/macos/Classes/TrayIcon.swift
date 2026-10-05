import SwiftUI
//
//  TrayIcon.swift
//  tray_manager
//
//  Created by Lijy91 on 2022/5/15.
//

public class TrayIcon: NSView {
    public var onTrayIconMouseDown:(() -> Void)?
    public var onTrayIconMouseUp:(() -> Void)?
    public var onTrayIconRightMouseDown:(() -> Void)?
    public var onTrayIconRightMouseUp:(() -> Void)?
    
    var statusItem: NSStatusItem?
    
    var textAttributes: [NSAttributedString.Key : Any]?
    
    private let imageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.isHidden = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }()
    
    private let textField: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isBezeled = false
        field.isHidden = true
        field.drawsBackground = false
        field.cell?.wraps = false
        field.alignment = .right
        return field
    }()
    
    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.distribution = .equalSpacing
        return stack
    }()
    
    
    public init() {
        super.init(frame: NSRect.zero)
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = 9
        paragraphStyle.minimumLineHeight = 9
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byClipping
        
        textAttributes = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: 8.75),
            .foregroundColor: NSColor.labelColor
        ]
        
        if let button = statusItem?.button {
            button.addSubview(self)
            self.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                self.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                self.topAnchor.constraint(equalTo: button.topAnchor),
                self.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                self.heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),
            ])
            setupView()
        }
    }
    
    private func setupView() {
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor,constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor,constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor,constant:2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor,constant:-2),
        ])
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 42),
            textField.trailingAnchor.constraint(equalTo:stackView.trailingAnchor),
        ])
    }
    
    
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect);
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setImage(_ image: NSImage, _ imagePosition: String) {
        imageView.image = image
        imageView.isHidden = false
        if let button = statusItem?.button {
            button.sizeToFit()
        }
    }
    
    public func setImagePosition(_ imagePosition: String) {
        self.frame = statusItem!.button!.frame
    }
    
    public func removeImage() {
        statusItem?.button?.image = nil
        self.frame = statusItem!.button!.frame
    }
    
    /// 上次真正落咗去嘅标题。见 setTitle 入面嘅解释。
    private var lastTitle: String?

    public func setTitle(_ title: String) {
        // 🔴 [2026-09-23] macOS 闲置高 CPU 嘅真凶就喺呢个函数。
        //
        // 原本每次 setTitle 都无条件 `button.sizeToFit()`,而 App 嗰边**每秒**都会
        // 落一次标题(流量数字每秒变;就算用户关咗托盘标题,旧代码都照落空字符串)。
        // `sizeToFit()` 会触发 **NSStatusItem 完整重绘** ——
        // 上游 issue #1644 / #2141 实测:0.8.93 窗口隐藏 + 托盘标题已关,
        // GUI 仍然食 36.7–40.0% CPU,5 秒采样入面 `_updateReplicants` 主路径 542 个样本;
        // 加咗去重之后 0.0–0.5%(4349 个样本得 3 个)。另一用户退出 App 之后
        // **WindowServer 由 44–53% 跌到 14.6–37.3%**。多显示器仲会放大。
        //
        // 修法两层:
        //   ① 内容冇变就即刻返(呢度 + `lib/common/tray.dart` 双保险)
        //   ② **只喺显隐状态变化先 sizeToFit** —— `textField` 係 Auto Layout
        //      **固定宽度 42pt**(见 setupView)、`lineBreakMode = .byClipping`,
        //      所以文本内容变**根本唔会改变尺寸**,嗰阵 sizeToFit 係纯浪费。
        //      只有 isHidden 变咗先会令 NSStackView 收缩 / 展开,嗰阵先真係要重新量。
        if lastTitle == title { return }
        let wasHidden = textField.isHidden
        lastTitle = title
        textField.attributedStringValue = NSAttributedString(string: title, attributes: textAttributes)
        textField.isHidden = title.isEmpty
        if textField.isHidden != wasHidden, let button = statusItem?.button {
            button.sizeToFit()
        }
    }
    
    public func setToolTip(_ toolTip: String) {
        if let button = statusItem?.button {
            button.toolTip  = toolTip
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        statusItem?.button?.highlight(true)
        self.onTrayIconMouseDown!()
    }
    
    public override func mouseUp(with event: NSEvent) {
        statusItem?.button?.highlight(false)
        self.onTrayIconMouseUp!()
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        self.onTrayIconRightMouseDown!()
    }
    
    public override func rightMouseUp(with event: NSEvent) {
        self.onTrayIconRightMouseUp!()
    }
}
