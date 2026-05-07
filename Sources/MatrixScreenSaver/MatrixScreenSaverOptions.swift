import AppKit
import ScreenSaver

struct MatrixScreenSaverOptions: Equatable {
    private enum Keys {
        static let numberSceneEnabled = "NumberSceneEnabled"
        static let twinkleEnabled = "TwinkleEnabled"
        static let diffuseEnabled = "DiffuseEnabled"
        static let characterWidth = "CharacterWidth"
        static let characterHeight = "CharacterHeight"
        static let rainDensity = "RainDensity"
        static let frameRate = "FrameRate"
        static let errorRate = "ErrorRate"
    }

    static let defaultNumberSceneEnabled = true
    static let defaultTwinkleEnabled = true
    static let defaultDiffuseEnabled = true
    static let defaultCharacterWidth = 8
    static let defaultCharacterHeight = 15
    static let defaultRainDensity = 1.0
    static let defaultFrameRate = 25.0
    static let defaultErrorRate = 1.0

    static let minimumRainDensity = 0.0001
    static let minimumFrameRate = 0.0001
    static let maximumFrameRate = 1000.0
    static let minimumErrorRate = 0.0
    static let minimumCharacterWidth = 1
    static let minimumCharacterHeight = 1

    static let numberSceneDescription = "Show the startup number scene before continuous rain. Turned on by default."
    static let diffuseDescription = "Turn on/off the glow effect. Turned on by default."
    static let twinkleDescription = "Turn on/off the twinkling effect. Turned on by default."
    static let characterSizeDescription = "Set the character cell width and height in pixels. The default is 8x15."
    static let rainDensityDescription = "Set the factor for the density of rain drops. A positive number. The default is 1.0."
    static let frameRateDescription = "Set the frame rate per second. A positive number less than or equal to 1000. The default is 25."
    static let errorRateDescription = "Set the factor for the rate of character changes. A non-negative number. The default is 1.0."

    var numberSceneEnabled = defaultNumberSceneEnabled
    var twinkleEnabled = defaultTwinkleEnabled
    var diffuseEnabled = defaultDiffuseEnabled
    var characterWidth = defaultCharacterWidth
    var characterHeight = defaultCharacterHeight
    var rainDensity = defaultRainDensity
    var frameRate = defaultFrameRate
    var errorRate = defaultErrorRate

    /// Converts persisted options into the renderer configuration type.
    func rendererConfiguration() -> NativeMatrixRenderer.Configuration {
        NativeMatrixRenderer.Configuration(
            numberSceneEnabled: numberSceneEnabled,
            twinkleEnabled: twinkleEnabled,
            diffuseEnabled: diffuseEnabled,
            rainDensity: rainDensity,
            frameRate: frameRate,
            errorRate: errorRate
        )
    }

    /// Clamps persisted values to the supported ranges.
    func sanitized() -> MatrixScreenSaverOptions {
        MatrixScreenSaverOptions(
            numberSceneEnabled: numberSceneEnabled,
            twinkleEnabled: twinkleEnabled,
            diffuseEnabled: diffuseEnabled,
            characterWidth: max(characterWidth, Self.minimumCharacterWidth),
            characterHeight: max(characterHeight, Self.minimumCharacterHeight),
            rainDensity: max(rainDensity, Self.minimumRainDensity),
            frameRate: min(max(frameRate, Self.minimumFrameRate), Self.maximumFrameRate),
            errorRate: max(errorRate, Self.minimumErrorRate)
        )
    }

    /// Registers the default option values with the screen saver defaults store.
    static func registerDefaults(in defaults: ScreenSaverDefaults) {
        defaults.register(defaults: [
            Keys.numberSceneEnabled: defaultNumberSceneEnabled,
            Keys.twinkleEnabled: defaultTwinkleEnabled,
            Keys.diffuseEnabled: defaultDiffuseEnabled,
            Keys.characterWidth: defaultCharacterWidth,
            Keys.characterHeight: defaultCharacterHeight,
            Keys.rainDensity: defaultRainDensity,
            Keys.frameRate: defaultFrameRate,
            Keys.errorRate: defaultErrorRate,
        ])
    }

    /// Loads the persisted options from the screen saver defaults store.
    static func load(from defaults: ScreenSaverDefaults) -> MatrixScreenSaverOptions {
        MatrixScreenSaverOptions(
            numberSceneEnabled: defaults.bool(forKey: Keys.numberSceneEnabled),
            twinkleEnabled: defaults.bool(forKey: Keys.twinkleEnabled),
            diffuseEnabled: defaults.bool(forKey: Keys.diffuseEnabled),
            characterWidth: defaults.integer(forKey: Keys.characterWidth),
            characterHeight: defaults.integer(forKey: Keys.characterHeight),
            rainDensity: defaults.double(forKey: Keys.rainDensity),
            frameRate: defaults.double(forKey: Keys.frameRate),
            errorRate: defaults.double(forKey: Keys.errorRate)
        ).sanitized()
    }

    /// Saves the current options back to the screen saver defaults store.
    func save(to defaults: ScreenSaverDefaults) {
        let options = sanitized()
        defaults.set(options.numberSceneEnabled, forKey: Keys.numberSceneEnabled)
        defaults.set(options.twinkleEnabled, forKey: Keys.twinkleEnabled)
        defaults.set(options.diffuseEnabled, forKey: Keys.diffuseEnabled)
        defaults.set(options.characterWidth, forKey: Keys.characterWidth)
        defaults.set(options.characterHeight, forKey: Keys.characterHeight)
        defaults.set(options.rainDensity, forKey: Keys.rainDensity)
        defaults.set(options.frameRate, forKey: Keys.frameRate)
        defaults.set(options.errorRate, forKey: Keys.errorRate)
        defaults.synchronize()
    }
}

final class MatrixScreenSaverOptionsSheetController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private enum ValidationError: LocalizedError {
        case characterWidth
        case characterHeight
        case rainDensity
        case frameRate
        case errorRate

        var errorDescription: String? {
            switch self {
            case .characterWidth:
                return "Character width must be a positive whole number."
            case .characterHeight:
                return "Character height must be a positive whole number."
            case .rainDensity:
                return "Rain density must be a positive number."
            case .frameRate:
                return "Frame rate must be a positive number less than or equal to 1000."
            case .errorRate:
                return "Error rate must be a non-negative number."
            }
        }
    }

    private weak var owner: MatrixScreenSaverView?
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let rootStack = NSStackView()
    private let numberSceneCheckbox = NSButton(checkboxWithTitle: "Number scene", target: nil, action: nil)
    private let twinkleCheckbox = NSButton(checkboxWithTitle: "Twinkle", target: nil, action: nil)
    private let diffuseCheckbox = NSButton(checkboxWithTitle: "Diffuse", target: nil, action: nil)
    private let characterWidthField = NSTextField(string: "")
    private let characterHeightField = NSTextField(string: "")
    private let rainDensityField = NSTextField(string: "")
    private let frameRateField = NSTextField(string: "")
    private let errorRateField = NSTextField(string: "")
    private var didClose = false

    /// Creates the options sheet controller for a specific saver view instance.
    init(owner: MatrixScreenSaverView) {
        self.owner = owner
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildWindow()
    }

    /// Updates all controls from the supplied options snapshot.
    func prepare(using options: MatrixScreenSaverOptions) {
        numberSceneCheckbox.state = options.numberSceneEnabled ? .on : .off
        twinkleCheckbox.state = options.twinkleEnabled ? .on : .off
        diffuseCheckbox.state = options.diffuseEnabled ? .on : .off
        characterWidthField.stringValue = Self.format(options.characterWidth)
        characterHeightField.stringValue = Self.format(options.characterHeight)
        rainDensityField.stringValue = Self.format(options.rainDensity)
        frameRateField.stringValue = Self.format(options.frameRate)
        errorRateField.stringValue = Self.format(options.errorRate)
        sizeWindowToFitContent()
    }

    /// Returns the native sheet window presented by ScreenSaver.framework.
    func configureSheet() -> NSWindow {
        window
    }

    /// Validates and applies the edited options.
    @objc private func apply(_ sender: Any?) {
        do {
            guard let owner else {
                closeSheet(with: .cancel)
                return
            }
            let options = try validatedOptions()
            owner.applySaverOptionsFromSheet(options)
            closeSheet(with: .OK)
        } catch {
            presentValidationAlert(message: error.localizedDescription)
        }
    }

    /// Dismisses the sheet without persisting any changes.
    @objc private func cancel(_ sender: Any?) {
        closeSheet(with: .cancel)
    }

    /// Restores the controls to the default option values.
    @objc private func resetToDefaults(_ sender: Any?) {
        prepare(using: MatrixScreenSaverOptions())
    }

    /// Constructs the native AppKit options sheet content and layout.
    private func buildWindow() {
        window.title = "MatrixScreenSaver Options"
        window.isReleasedWhenClosed = false
        window.delegate = self

        characterWidthField.formatter = Self.integerFormatter
        characterHeightField.formatter = Self.integerFormatter
        rainDensityField.formatter = Self.numberFormatter
        frameRateField.formatter = Self.numberFormatter
        errorRateField.formatter = Self.numberFormatter
        characterWidthField.delegate = self
        characterHeightField.delegate = self
        rainDensityField.delegate = self
        frameRateField.delegate = self
        errorRateField.delegate = self

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let numberSceneSection = makeCheckboxSection(
            checkbox: numberSceneCheckbox,
            description: MatrixScreenSaverOptions.numberSceneDescription
        )
        let twinkleSection = makeCheckboxSection(checkbox: twinkleCheckbox, description: MatrixScreenSaverOptions.twinkleDescription)
        let diffuseSection = makeCheckboxSection(checkbox: diffuseCheckbox, description: MatrixScreenSaverOptions.diffuseDescription)
        let toggleStack = NSStackView()
        toggleStack.orientation = .vertical
        toggleStack.alignment = .leading
        toggleStack.spacing = 16
        toggleStack.setHuggingPriority(.required, for: .vertical)
        toggleStack.addArrangedSubview(numberSceneSection)
        toggleStack.addArrangedSubview(twinkleSection)
        toggleStack.addArrangedSubview(diffuseSection)
        rootStack.addArrangedSubview(toggleStack)
        rootStack.addArrangedSubview(makeCharacterSizeSection())
        rootStack.addArrangedSubview(makeNumericSection(title: "Rain density", field: rainDensityField, description: MatrixScreenSaverOptions.rainDensityDescription))
        rootStack.addArrangedSubview(makeNumericSection(title: "Frame rate", field: frameRateField, description: MatrixScreenSaverOptions.frameRateDescription))
        rootStack.addArrangedSubview(makeNumericSection(title: "Error rate", field: errorRateField, description: MatrixScreenSaverOptions.errorRateDescription))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset to defaults", target: self, action: #selector(resetToDefaults(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let okButton = NSButton(title: "OK", target: self, action: #selector(apply(_:)))
        okButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(okButton)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.translatesAutoresizingMaskIntoConstraints = false

        let leadingPadding = NSView()
        leadingPadding.translatesAutoresizingMaskIntoConstraints = false
        leadingPadding.widthAnchor.constraint(equalToConstant: rootStack.edgeInsets.left).isActive = true
        leadingPadding.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        footer.addArrangedSubview(leadingPadding)
        footer.addArrangedSubview(resetButton)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(buttons)
        footer.setCustomSpacing(0, after: leadingPadding)

        rootStack.addArrangedSubview(footer)
        buttons.setHuggingPriority(.required, for: .horizontal)
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])

        sizeWindowToFitContent()
    }

    /// Builds a checkbox row with its explanatory description.
    private func makeCheckboxSection(checkbox: NSButton, description: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        checkbox.setButtonType(.switch)
        stack.addArrangedSubview(checkbox)
        stack.addArrangedSubview(makeDescriptionLabel(description))
        return stack
    }

    /// Builds a labeled numeric input row with its description.
    private func makeNumericSection(title: String, field: NSTextField, description: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)

        field.alignment = .left
        field.controlSize = .regular
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.fourDigitFieldWidth).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(field)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(description))
        return stack
    }

    /// Builds the side-by-side character width and height controls.
    private func makeCharacterSizeSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let titleLabel = NSTextField(labelWithString: "Character size")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let widthLabel = NSTextField(labelWithString: "Width")
        widthLabel.setContentHuggingPriority(.required, for: .horizontal)
        characterWidthField.alignment = .left
        characterWidthField.controlSize = .regular
        characterWidthField.translatesAutoresizingMaskIntoConstraints = false
        characterWidthField.widthAnchor.constraint(equalToConstant: Self.threeDigitFieldWidth).isActive = true

        let heightLabel = NSTextField(labelWithString: "Height")
        heightLabel.setContentHuggingPriority(.required, for: .horizontal)
        characterHeightField.alignment = .left
        characterHeightField.controlSize = .regular
        characterHeightField.translatesAutoresizingMaskIntoConstraints = false
        characterHeightField.widthAnchor.constraint(equalToConstant: Self.threeDigitFieldWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(widthLabel)
        row.addArrangedSubview(characterWidthField)
        row.addArrangedSubview(heightLabel)
        row.addArrangedSubview(characterHeightField)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.characterSizeDescription))
        return stack
    }

    /// Creates the smaller descriptive text used under each option row.
    private func makeDescriptionLabel(_ description: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: description)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return label
    }

    /// Validates all control values and returns a sanitized options snapshot.
    private func validatedOptions() throws -> MatrixScreenSaverOptions {
        let characterWidth = try parseInteger(from: characterWidthField, error: .characterWidth)
        let characterHeight = try parseInteger(from: characterHeightField, error: .characterHeight)
        let rainDensity = try parseDouble(from: rainDensityField, error: .rainDensity)
        let frameRate = try parseDouble(from: frameRateField, error: .frameRate)
        let errorRate = try parseDouble(from: errorRateField, error: .errorRate)

        guard characterWidth > 0 else {
            throw ValidationError.characterWidth
        }
        guard characterHeight > 0 else {
            throw ValidationError.characterHeight
        }
        guard rainDensity > 0 else {
            throw ValidationError.rainDensity
        }
        guard frameRate > 0, frameRate <= MatrixScreenSaverOptions.maximumFrameRate else {
            throw ValidationError.frameRate
        }
        guard errorRate >= 0 else {
            throw ValidationError.errorRate
        }

        return MatrixScreenSaverOptions(
            numberSceneEnabled: numberSceneCheckbox.state == .on,
            twinkleEnabled: twinkleCheckbox.state == .on,
            diffuseEnabled: diffuseCheckbox.state == .on,
            characterWidth: characterWidth,
            characterHeight: characterHeight,
            rainDensity: rainDensity,
            frameRate: frameRate,
            errorRate: errorRate
        ).sanitized()
    }

    /// Parses and validates an integer field.
    private func parseInteger(from field: NSTextField, error: ValidationError) throws -> Int {
        let trimmed = Self.normalizedIntegerText(field.stringValue)
        field.stringValue = trimmed
        guard let value = Int(trimmed) else {
            throw error
        }
        return value
    }

    /// Parses and validates a decimal field.
    private func parseDouble(from field: NSTextField, error: ValidationError) throws -> Double {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizedDecimalText(trimmed)
        field.stringValue = normalized
        guard let value = Double(normalized) else {
            throw error
        }
        return value
    }

    /// Normalizes edited text before AppKit ends text field editing.
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let normalized: String
        if control === characterWidthField || control === characterHeightField {
            normalized = Self.normalizedIntegerText(fieldEditor.string)
        } else {
            normalized = Self.normalizedDecimalText(fieldEditor.string)
        }
        fieldEditor.string = normalized
        if let textField = control as? NSTextField {
            textField.stringValue = normalized
        }
        return true
    }

    /// Routes the window close button through the sheet dismissal path.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeSheet(with: .cancel)
        return false
    }

    /// Finalizes cleanup when the sheet window closes.
    func windowWillClose(_ notification: Notification) {
        finishClosing()
    }

    /// Presents a native validation error alert above the options sheet.
    private func presentValidationAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid option value"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    /// Closes the sheet with the provided modal response code.
    private func closeSheet(with returnCode: NSApplication.ModalResponse) {
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window, returnCode: returnCode)
        }
        window.orderOut(nil)
        finishClosing()
    }

    /// Runs the one-time close callback shared by all dismissal paths.
    private func finishClosing() {
        guard !didClose else {
            return
        }
        didClose = true
        onClose?()
    }

    /// Formats a decimal option for display in a text field.
    private static func format(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Formats an integer option for display in a text field.
    private static func format(_ value: Int) -> String {
        "\(value)"
    }

    /// Normalizes decimal text to use a period separator.
    private static func normalizedDecimalText(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: ".")
    }

    /// Trims integer text before parsing.
    private static func normalizedIntegerText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resizes the sheet window so it fits the current stack view content.
    private func sizeWindowToFitContent() {
        guard let contentView = window.contentView else {
            return
        }

        contentView.layoutSubtreeIfNeeded()
        let fittingSize = rootStack.fittingSize
        let contentSize = NSSize(
            width: ceil(fittingSize.width + rootStack.edgeInsets.right),
            height: ceil(fittingSize.height)
        )
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
    }

    private static let fourDigitFieldWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidth = ceil(("0000" as NSString).size(withAttributes: [.font: font]).width)
        return textWidth + 20
    }()

    private static let threeDigitFieldWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidth = ceil(("000" as NSString).size(withAttributes: [.font: font]).width)
        return textWidth + 20
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
