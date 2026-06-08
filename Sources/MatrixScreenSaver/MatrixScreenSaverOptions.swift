import AppKit
import ScreenSaver

struct MatrixScreenSaverOptions: Equatable {
    private enum Keys {
        static let neoMessageSceneEnabled = "NeoMessageSceneEnabled"
        static let neoMessageSpeedFactor = "NeoMessageSpeedFactor"
        static let neoMessageLines = "NeoMessageLines"
        static let numberSceneEnabled = "NumberSceneEnabled"
        static let twinkleEnabled = "TwinkleEnabled"
        static let diffuseEnabled = "DiffuseEnabled"
        static let characterWidth = "CharacterWidth"
        static let characterHeight = "CharacterHeight"
        static let rainDensity = "RainDensity"
         static let rainRunForever = "RainRunForever"
         static let rainDurationSeconds = "RainDurationSeconds"
         static let frameRate = "FrameRate"
        static let errorRate = "ErrorRate"
        static let characters = "Characters"
        static let scanLinesIntensity = "ScanLinesIntensity"
        static let scanLinesVertical = "ScanLinesVertical"
    }

    static let defaultNeoMessageSceneEnabled = true
    static let defaultNeoMessageSpeedFactor = 1.0
    static let defaultNeoMessageLines = NeoMessageScene.defaultLines
    static let defaultNumberSceneEnabled = true
    static let defaultTwinkleEnabled = true
    static let defaultDiffuseEnabled = true
    static let defaultCharacterWidth = 16
    static let defaultCharacterHeight = 30
     static let defaultRainDensity = 1.0
     static let defaultRainRunForever = true
     static let defaultRainDurationSeconds = 300
     static let defaultFrameRate = 25.0
    static let defaultErrorRate = 1.0
    static let defaultCharacters = ""
    static let defaultScanLinesIntensity = 0.25
    static let defaultScanLinesVertical = true

    static let minimumRainDensity = MatrixRendererLimits.minimumRainDensity
    static let minimumFrameRate = MatrixRendererLimits.minimumFrameRate
    static let maximumFrameRate = MatrixRendererLimits.maximumFrameRate
    static let minimumErrorRate = MatrixRendererLimits.minimumErrorRate
    static let minimumNeoMessageSpeedFactor = MatrixRendererLimits.minimumNeoMessageSpeedFactor
    static let minimumCharacterWidth = 1
    static let minimumCharacterHeight = 1
     static let minNeoMessageLineCount = 1
     static let maxNeoMessageLineCount = 10
     static let maxNeoMessageLineLength = 256
     static let minimumRainDurationSeconds = 1
     static let maximumRainDurationSeconds = 9999

    static let neoMessageSceneDescription = "Show the Neo message intro. On by default."
    static let neoMessageSpeedFactorDescription = "Speed multiplier for intro scene typing (Neo message and number scene). Default: 1.0."
    static let neoMessageLinesDescription = "Lines typed during the Neo message intro (1–10, max 256 chars)."
    static let numberSceneDescription = "Show the startup number scene. On by default."
    static let diffuseDescription = "On by default."
    static let twinkleDescription = "On by default."
    static let characterSizeDescription = "Character cell size in pixels. Default: 16×30."

    static let characterSizePairs: [(width: Int, height: Int)] = [
        (8, 15), (9, 17), (10, 19), (11, 21), (12, 23), (13, 24), (14, 26), (15, 28), (16, 30), (17, 32), (18, 34), (19, 36), (20, 38), (21, 40), (22, 42), (23, 44), (24, 46)
    ]
    static let defaultCharacterSizeIndex = 8
     static let rainDensityDescription = "Rain density multiplier. Default: 1.0."
     static let rainRunForeverDescription = "When enabled (default), rain continuously spawns new falling lines. When disabled, rain stops starting new lines after the specified duration; lines already falling finish and fade out, then the full scene sequence restarts."
     static let rainDurationSecondsDescription = "How long rain keeps starting new falling lines (1–9999 seconds) before it winds down. Default: 300 (5 minutes)."
     static let frameRateDescription = "Target frame rate in fps, 1–1000. Default: 25."
    static let errorRateDescription = "Character change rate factor. Default: 1.0."
    static let charactersDescription = "Custom glyph set (e.g. ATGC). Empty = default."
    static let scanLinesDescription = "CRT scan line intensity (0–100%). Default: 25%."

    var neoMessageSceneEnabled = defaultNeoMessageSceneEnabled
    var neoMessageSpeedFactor = defaultNeoMessageSpeedFactor
    var neoMessageLines = defaultNeoMessageLines
    var numberSceneEnabled = defaultNumberSceneEnabled
    var twinkleEnabled = defaultTwinkleEnabled
    var diffuseEnabled = defaultDiffuseEnabled
    var characterWidth = defaultCharacterWidth
    var characterHeight = defaultCharacterHeight
     var rainDensity = defaultRainDensity
     var rainRunForever = defaultRainRunForever
     var rainDurationSeconds = defaultRainDurationSeconds
     var frameRate = defaultFrameRate
    var errorRate = defaultErrorRate
    var characters = defaultCharacters
    var scanLinesIntensity = defaultScanLinesIntensity
    var scanLinesVertical = defaultScanLinesVertical

    /// Converts persisted options into the renderer configuration type.
    func rendererConfiguration(isPreview: Bool = false) -> NativeMatrixRenderer.Configuration {
        NativeMatrixRenderer.Configuration(
            neoMessageSceneEnabled: neoMessageSceneEnabled,
            neoMessageSpeedFactor: neoMessageSpeedFactor,
            numberSceneEnabled: numberSceneEnabled,
            twinkleEnabled: twinkleEnabled,
            diffuseEnabled: diffuseEnabled,
            rainDensity: rainDensity,
             rainRunForever: rainRunForever,
             rainDurationSeconds: rainDurationSeconds,
             frameRate: frameRate,
            errorRate: errorRate,
            characters: characters,
            neoMessageLines: neoMessageLines,
            skipSyncDelay: isPreview
        )
    }

    /// Clamps persisted values to the supported ranges.
    func sanitized() -> MatrixScreenSaverOptions {
        let sanitizedLines: [String] = {
            let result = neoMessageLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { String($0.prefix(Self.maxNeoMessageLineLength)) }
                .filter { !$0.isEmpty }
            let clamped = Array(result.prefix(Self.maxNeoMessageLineCount))
            return clamped.isEmpty ? Self.defaultNeoMessageLines : clamped
        }()
        return MatrixScreenSaverOptions(
            neoMessageSceneEnabled: neoMessageSceneEnabled,
            neoMessageSpeedFactor: max(neoMessageSpeedFactor, Self.minimumNeoMessageSpeedFactor),
            neoMessageLines: sanitizedLines,
            numberSceneEnabled: numberSceneEnabled,
            twinkleEnabled: twinkleEnabled,
            diffuseEnabled: diffuseEnabled,
            characterWidth: max(characterWidth, Self.minimumCharacterWidth),
            characterHeight: max(characterHeight, Self.minimumCharacterHeight),
             rainDensity: max(rainDensity, Self.minimumRainDensity),
             rainRunForever: rainRunForever,
             rainDurationSeconds: min(max(rainDurationSeconds, Self.minimumRainDurationSeconds), Self.maximumRainDurationSeconds),
             frameRate: min(max(frameRate, Self.minimumFrameRate), Self.maximumFrameRate),
            errorRate: max(errorRate, Self.minimumErrorRate),
            characters: {
                var seen = Set<UnicodeScalar>()
                return characters
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .unicodeScalars
                    .filter { s in
                        !s.properties.isDiacritic &&
                        !CharacterSet.whitespacesAndNewlines.contains(s) &&
                        !CharacterSet.controlCharacters.contains(s) &&
                        seen.insert(s).inserted
                    }
                    .map { String($0) }
                    .joined()
            }(),
            scanLinesIntensity: max(0, min(1, scanLinesIntensity)),
            scanLinesVertical: scanLinesVertical
        )
    }

    /// Registers the default option values with the screen saver defaults store.
    static func registerDefaults(in defaults: ScreenSaverDefaults) {
        defaults.register(defaults: [
            Keys.neoMessageSceneEnabled: defaultNeoMessageSceneEnabled,
            Keys.neoMessageSpeedFactor: defaultNeoMessageSpeedFactor,
            Keys.neoMessageLines: defaultNeoMessageLines,
            Keys.numberSceneEnabled: defaultNumberSceneEnabled,
            Keys.twinkleEnabled: defaultTwinkleEnabled,
            Keys.diffuseEnabled: defaultDiffuseEnabled,
            Keys.characterWidth: defaultCharacterWidth,
            Keys.characterHeight: defaultCharacterHeight,
             Keys.rainDensity: defaultRainDensity,
             Keys.rainRunForever: defaultRainRunForever,
             Keys.rainDurationSeconds: defaultRainDurationSeconds,
             Keys.frameRate: defaultFrameRate,
            Keys.errorRate: defaultErrorRate,
            Keys.characters: defaultCharacters,
            Keys.scanLinesIntensity: defaultScanLinesIntensity,
            Keys.scanLinesVertical: defaultScanLinesVertical,
        ])
    }

    /// Loads the persisted options from the screen saver defaults store.
    static func load(from defaults: ScreenSaverDefaults) -> MatrixScreenSaverOptions {
        MatrixScreenSaverOptions(
            neoMessageSceneEnabled: defaults.bool(forKey: Keys.neoMessageSceneEnabled),
            neoMessageSpeedFactor: defaults.double(forKey: Keys.neoMessageSpeedFactor),
            neoMessageLines: (defaults.array(forKey: Keys.neoMessageLines) as? [String]) ?? defaultNeoMessageLines,
            numberSceneEnabled: defaults.bool(forKey: Keys.numberSceneEnabled),
            twinkleEnabled: defaults.bool(forKey: Keys.twinkleEnabled),
            diffuseEnabled: defaults.bool(forKey: Keys.diffuseEnabled),
            characterWidth: defaults.integer(forKey: Keys.characterWidth),
            characterHeight: defaults.integer(forKey: Keys.characterHeight),
             rainDensity: defaults.double(forKey: Keys.rainDensity),
             rainRunForever: defaults.bool(forKey: Keys.rainRunForever),
             rainDurationSeconds: defaults.integer(forKey: Keys.rainDurationSeconds),
             frameRate: defaults.double(forKey: Keys.frameRate),
            errorRate: defaults.double(forKey: Keys.errorRate),
            characters: defaults.string(forKey: Keys.characters) ?? defaultCharacters,
            scanLinesIntensity: defaults.double(forKey: Keys.scanLinesIntensity),
            scanLinesVertical: defaults.bool(forKey: Keys.scanLinesVertical)
        ).sanitized()
    }

    /// Saves the current options back to the screen saver defaults store.
    func save(to defaults: ScreenSaverDefaults) {
        let options = sanitized()
        defaults.set(options.neoMessageSceneEnabled, forKey: Keys.neoMessageSceneEnabled)
        defaults.set(options.neoMessageSpeedFactor, forKey: Keys.neoMessageSpeedFactor)
        defaults.set(options.neoMessageLines, forKey: Keys.neoMessageLines)
        defaults.set(options.numberSceneEnabled, forKey: Keys.numberSceneEnabled)
        defaults.set(options.twinkleEnabled, forKey: Keys.twinkleEnabled)
        defaults.set(options.diffuseEnabled, forKey: Keys.diffuseEnabled)
        defaults.set(options.characterWidth, forKey: Keys.characterWidth)
        defaults.set(options.characterHeight, forKey: Keys.characterHeight)
         defaults.set(options.rainDensity, forKey: Keys.rainDensity)
         defaults.set(options.rainRunForever, forKey: Keys.rainRunForever)
         defaults.set(options.rainDurationSeconds, forKey: Keys.rainDurationSeconds)
         defaults.set(options.frameRate, forKey: Keys.frameRate)
        defaults.set(options.errorRate, forKey: Keys.errorRate)
        defaults.set(options.characters, forKey: Keys.characters)
        defaults.set(options.scanLinesIntensity, forKey: Keys.scanLinesIntensity)
        defaults.set(options.scanLinesVertical, forKey: Keys.scanLinesVertical)
        defaults.synchronize()
    }
}

final class MatrixScreenSaverOptionsSheetController: NSObject,
    NSTextFieldDelegate, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
     private enum ValidationError: LocalizedError {
         case neoMessageSpeedFactor
          case rainDensity
           case frameRate
           case errorRate
           case rainDurationSeconds

         var errorDescription: String? {
             switch self {
             case .neoMessageSpeedFactor:
                 return "Neo message speed must be a positive number."
             case .rainDensity:
                 return "Rain density must be a positive number."
             case .frameRate:
                 return "Frame rate must be a positive number less than or equal to 1000."
             case .errorRate:
               return "Error rate must be a non-negative number."
               case .rainDurationSeconds:
                   return "Rain duration must be a positive integer (1–9999 seconds)."
             }
         }
     }

    private weak var owner: MatrixScreenSaverView?
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let rootStack = NSStackView()
    private let neoMessageSceneCheckbox = NSButton(checkboxWithTitle: "Activate", target: nil, action: nil)
    private let neoMessageSpeedFactorField = NSTextField(string: "")
    private let linesTableView = NSTableView()
    private let linesScrollView = NSScrollView()
    private var editorLines: [String] = []
    private var linesScrollHeightConstraint: NSLayoutConstraint?
    private var linesEditorAddButton = NSButton(title: "+", target: nil, action: nil)
    private static let lineRowHeight: CGFloat = 24
    private static let dragPboardType = NSPasteboard.PasteboardType("matrixss.lineRow")
    private static let handleColumnID = NSUserInterfaceItemIdentifier("handle")
    private static let textColumnID   = NSUserInterfaceItemIdentifier("lineText")
    private static let removeColumnID = NSUserInterfaceItemIdentifier("remove")
    private var pendingLines: [String] = MatrixScreenSaverOptions.defaultNeoMessageLines
    private var linesEditorWindow: NSWindow?
    private let numberSceneCheckbox = NSButton(checkboxWithTitle: "Activate", target: nil, action: nil)
    private let twinkleCheckbox = NSButton(checkboxWithTitle: "Twinkling effect", target: nil, action: nil)
    private let diffuseCheckbox = NSButton(checkboxWithTitle: "Glow effect", target: nil, action: nil)
    private let scanLinesSlider: NSSlider = {
        let s = NSSlider(value: MatrixScreenSaverOptions.defaultScanLinesIntensity * 100,
                         minValue: 0, maxValue: 100,
                         target: nil, action: nil)
        s.numberOfTickMarks = 0
        s.allowsTickMarkValuesOnly = false
        return s
    }()
    private let scanLinesValueLabel = NSTextField(labelWithString: "25%")
    private let scanLinesDirectionPopup: NSPopUpButton = {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Vertical", "Horizontal"])
        popup.setContentHuggingPriority(.required, for: .horizontal)
        return popup
    }()
    private let characterSizeSlider: NSSlider = {
        let pairs = MatrixScreenSaverOptions.characterSizePairs
        let s = NSSlider(value: Double(MatrixScreenSaverOptions.defaultCharacterSizeIndex),
                         minValue: 0, maxValue: Double(pairs.count - 1),
                         target: nil, action: nil)
        s.numberOfTickMarks = pairs.count
        s.allowsTickMarkValuesOnly = true
        return s
    }()
    private let characterSizeValueLabel: NSTextField = {
        let pair = MatrixScreenSaverOptions.characterSizePairs[MatrixScreenSaverOptions.defaultCharacterSizeIndex]
        return NSTextField(labelWithString: "\(pair.width)×\(pair.height)")
    }()
     private let rainDensityField = NSTextField(string: "")
     private let rainRunForeverCheckbox = NSButton(checkboxWithTitle: "Run forever", target: nil, action: nil)
     private let rainDurationField = NSTextField(string: "")
     private let frameRateField = NSTextField(string: "")
    private let errorRateField = NSTextField(string: "")
    private let charactersField = NSTextField(string: "")
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
        neoMessageSceneCheckbox.state = options.neoMessageSceneEnabled ? .on : .off
        neoMessageSpeedFactorField.stringValue = Self.format(options.neoMessageSpeedFactor)
        pendingLines = options.neoMessageLines
        numberSceneCheckbox.state = options.numberSceneEnabled ? .on : .off
        twinkleCheckbox.state = options.twinkleEnabled ? .on : .off
        diffuseCheckbox.state = options.diffuseEnabled ? .on : .off
        scanLinesSlider.doubleValue = options.scanLinesIntensity * 100
        scanLinesValueLabel.stringValue = "\(Int(options.scanLinesIntensity * 100))%"
        scanLinesDirectionPopup.selectItem(at: options.scanLinesVertical ? 0 : 1)
        let sizeIndex = MatrixScreenSaverOptions.characterSizePairs.firstIndex(where: {
            $0.width == options.characterWidth && $0.height == options.characterHeight
        }) ?? MatrixScreenSaverOptions.defaultCharacterSizeIndex
        characterSizeSlider.doubleValue = Double(sizeIndex)
        let pair = MatrixScreenSaverOptions.characterSizePairs[sizeIndex]
        characterSizeValueLabel.stringValue = "\(pair.width)×\(pair.height)"
         rainDensityField.stringValue = Self.format(options.rainDensity)
         rainRunForeverCheckbox.state = options.rainRunForever ? .on : .off
         rainDurationField.stringValue = Self.format(options.rainDurationSeconds)
         rainDurationField.isEnabled = !options.rainRunForever
        frameRateField.stringValue = Self.format(options.frameRate)
        errorRateField.stringValue = Self.format(options.errorRate)
        charactersField.stringValue = options.characters
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

    /// Opens the repository URL in the default browser.
    @objc private func openRepository(_ sender: Any?) {
        if let url = URL(string: "https://github.com/patrickschaper/matrixScreenSaver") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Restores the controls to the default option values.
    @objc private func resetToDefaults(_ sender: Any?) {
        pendingLines = MatrixScreenSaverOptions.defaultNeoMessageLines
        prepare(using: MatrixScreenSaverOptions())
    }

    /// Constructs the native AppKit options sheet content and layout.
    private func buildWindow() {
        window.title = "MatrixScreenSaver Options"
        window.isReleasedWhenClosed = false
        window.delegate = self

         characterSizeSlider.target = self
         characterSizeSlider.action = #selector(characterSizeSliderChanged(_:))
         neoMessageSpeedFactorField.formatter = Self.numberFormatter
         rainDensityField.formatter = Self.numberFormatter
         rainDurationField.formatter = Self.integerFormatter
         frameRateField.formatter = Self.numberFormatter
         errorRateField.formatter = Self.numberFormatter
         neoMessageSpeedFactorField.delegate = self
         rainDensityField.delegate = self
         rainDurationField.delegate = self
         frameRateField.delegate = self
         errorRateField.delegate = self
         rainRunForeverCheckbox.target = self
         rainRunForeverCheckbox.action = #selector(rainRunForeverCheckboxChanged(_:))

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        // Header row: title left, About link right
        let headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "macOS Matrix Screen Saver")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let aboutButton = NSButton(title: "About", target: self, action: #selector(openRepository(_:)))
        aboutButton.bezelStyle = .inline
        aboutButton.isBordered = false
        aboutButton.contentTintColor = .linkColor
        aboutButton.font = .systemFont(ofSize: 13)
        aboutButton.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(titleLabel)
        headerContainer.addSubview(aboutButton)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            aboutButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            aboutButton.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            headerContainer.heightAnchor.constraint(equalTo: titleLabel.heightAnchor),
        ])
        rootStack.addArrangedSubview(headerContainer)

        let generalGroup = makeGroupBox(title: "General", views: [
            makeCharacterSizeSection(),
            makeScanLinesSection(),
            makeNumericSection(title: "Typing speed", field: neoMessageSpeedFactorField, description: MatrixScreenSaverOptions.neoMessageSpeedFactorDescription),
            makeNumericSection(title: "Frame rate", field: frameRateField, description: MatrixScreenSaverOptions.frameRateDescription),
        ])
        let neoGroup = makeGroupBox(title: "Neo message scene", views: [
            makeCheckboxSection(checkbox: neoMessageSceneCheckbox, description: MatrixScreenSaverOptions.neoMessageSceneDescription),
            makeNeoMessageLinesButtonRow(),
        ])
        let numberGroup = makeGroupBox(title: "Number scene", views: [
            makeCheckboxSection(checkbox: numberSceneCheckbox, description: MatrixScreenSaverOptions.numberSceneDescription),
        ])
         let rainGroup = makeGroupBox(title: "Rain scene", views: [
             makeCheckboxSection(checkbox: twinkleCheckbox, description: MatrixScreenSaverOptions.twinkleDescription),
             makeCheckboxSection(checkbox: diffuseCheckbox, description: MatrixScreenSaverOptions.diffuseDescription),
             makeNumericSection(title: "Density", field: rainDensityField, description: MatrixScreenSaverOptions.rainDensityDescription),
             makeRainDurationSection(),
             makeTextSection(title: "Characters", field: charactersField, description: MatrixScreenSaverOptions.charactersDescription, fieldWidth: Self.textFieldWidth / 2),
             makeNumericSection(title: "Error rate", field: errorRateField, description: MatrixScreenSaverOptions.errorRateDescription),
         ])
        rootStack.addArrangedSubview(generalGroup)
        rootStack.addArrangedSubview(neoGroup)
        rootStack.addArrangedSubview(numberGroup)
        rootStack.addArrangedSubview(rainGroup)

        let groupWidth = -(rootStack.edgeInsets.left + rootStack.edgeInsets.right)
        for group in [generalGroup, neoGroup, numberGroup, rainGroup] {
            group.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: groupWidth).isActive = true
        }

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

        let spacerLeft = NSView()
        spacerLeft.translatesAutoresizingMaskIntoConstraints = false
        spacerLeft.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let versionString = Bundle(for: MatrixScreenSaverOptionsSheetController.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: versionString.isEmpty ? "" : "v\(versionString)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)

        let spacerRight = NSView()
        spacerRight.translatesAutoresizingMaskIntoConstraints = false
        spacerRight.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerRight.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        footer.addArrangedSubview(resetButton)
        footer.addArrangedSubview(spacerLeft)
        footer.addArrangedSubview(versionLabel)
        footer.addArrangedSubview(spacerRight)
        footer.addArrangedSubview(buttons)

        rootStack.addArrangedSubview(footer)
        buttons.setHuggingPriority(.required, for: .horizontal)
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: groupWidth).isActive = true

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

    /// Builds the simple "Neo message lines [Edit…]" row shown in the main sheet.
    private func makeNeoMessageLinesButtonRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let label = NSTextField(labelWithString: "Lines")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)

        let editButton = NSButton(title: "Edit…", target: self, action: #selector(editLines(_:)))
        editButton.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(editButton)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.neoMessageLinesDescription))
        return stack
    }

    /// Builds the secondary Neo message lines editor window (presented as a sheet).
    private func buildLinesEditorWindow() -> NSWindow {
        let editorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        editorWindow.title = "Neo Message Lines"
        editorWindow.isReleasedWhenClosed = false

        // --- table setup ---
        let handleCol = NSTableColumn(identifier: Self.handleColumnID)
        handleCol.title = ""
        handleCol.width = 18
        handleCol.minWidth = 18
        handleCol.maxWidth = 18
        handleCol.resizingMask = []

        let textCol = NSTableColumn(identifier: Self.textColumnID)
        textCol.title = "Line"
        textCol.resizingMask = .autoresizingMask
        textCol.minWidth = 200

        let removeCol = NSTableColumn(identifier: Self.removeColumnID)
        removeCol.title = ""
        removeCol.width = 28
        removeCol.minWidth = 28
        removeCol.maxWidth = 28
        removeCol.resizingMask = []

        linesTableView.addTableColumn(handleCol)
        linesTableView.addTableColumn(textCol)
        linesTableView.addTableColumn(removeCol)
        linesTableView.headerView = nil
        linesTableView.rowHeight = Self.lineRowHeight
        linesTableView.intercellSpacing = NSSize(width: 4, height: 2)
        linesTableView.usesAlternatingRowBackgroundColors = false
        linesTableView.allowsMultipleSelection = false
        linesTableView.allowsEmptySelection = true
        linesTableView.dataSource = self
        linesTableView.delegate = self
        linesTableView.registerForDraggedTypes([Self.dragPboardType])
        linesTableView.draggingDestinationFeedbackStyle = .gap

        linesScrollView.documentView = linesTableView
        linesScrollView.hasVerticalScroller = false
        linesScrollView.hasHorizontalScroller = false
        linesScrollView.autohidesScrollers = true
        linesScrollView.borderType = .lineBorder
        linesScrollView.translatesAutoresizingMaskIntoConstraints = false

        // --- buttons ---
        linesEditorAddButton = NSButton(title: "+", target: self, action: #selector(addLine(_:)))
        linesEditorAddButton.bezelStyle = .rounded

        let resetLinesButton = NSButton(title: "Reset lines", target: self, action: #selector(resetLines(_:)))
        let cancelLinesButton = NSButton(title: "Cancel", target: self, action: #selector(cancelLines(_:)))
        let okLinesButton = NSButton(title: "OK", target: self, action: #selector(applyLines(_:)))
        okLinesButton.keyEquivalent = "\r"
        cancelLinesButton.keyEquivalent = "\u{1b}"

        let dialogButtons = NSStackView(views: [cancelLinesButton, okLinesButton])
        dialogButtons.orientation = .horizontal
        dialogButtons.spacing = 8

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(resetLinesButton)
        footer.addArrangedSubview(footerSpacer)
        footer.addArrangedSubview(dialogButtons)

        let editorStack = NSStackView()
        editorStack.orientation = .vertical
        editorStack.alignment = .leading
        editorStack.spacing = 12
        editorStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        editorStack.translatesAutoresizingMaskIntoConstraints = false

        editorStack.addArrangedSubview(linesScrollView)
        editorStack.addArrangedSubview(linesEditorAddButton)
        editorStack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.neoMessageLinesDescription))
        editorStack.addArrangedSubview(footer)

        linesScrollView.widthAnchor.constraint(equalTo: editorStack.widthAnchor,
            constant: -(editorStack.edgeInsets.left + editorStack.edgeInsets.right)).isActive = true
        footer.widthAnchor.constraint(equalTo: editorStack.widthAnchor,
            constant: -(editorStack.edgeInsets.left + editorStack.edgeInsets.right)).isActive = true

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(editorStack)
        editorWindow.contentView = contentView

        NSLayoutConstraint.activate([
            editorStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            editorStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            editorStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            editorStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])

        return editorWindow
    }

    /// Opens the lines editor as a sheet over the main options window.
    @objc private func editLines(_ sender: Any?) {
        let editor = linesEditorWindow ?? buildLinesEditorWindow()
        linesEditorWindow = editor
        editorLines = pendingLines
        linesTableView.reloadData()
        refreshLinesSection()
        window.beginSheet(editor)
    }

    /// Commits the editor lines and closes the editor sheet.
    @objc private func applyLines(_ sender: Any?) {
        flushEditorLines()
        pendingLines = editorLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(MatrixScreenSaverOptions.maxNeoMessageLineLength)) }
        if pendingLines.isEmpty { pendingLines = MatrixScreenSaverOptions.defaultNeoMessageLines }
        window.endSheet(linesEditorWindow ?? window)
    }

    /// Discards editor changes and closes the editor sheet.
    @objc private func cancelLines(_ sender: Any?) {
        window.endSheet(linesEditorWindow ?? window)
    }

    /// Syncs visible text-field values back into `editorLines` before a reload.
    private func flushEditorLines() {
        for row in 0..<linesTableView.numberOfRows {
            guard let cell = linesTableView.view(atColumn: 1, row: row, makeIfNecessary: false)
                    as? NSTableCellView,
                  let field = cell.textField else { continue }
            editorLines[row] = field.stringValue
        }
    }

    /// Adds a new empty line to the editor table.
    @objc private func addLine(_ sender: Any?) {
        guard editorLines.count < MatrixScreenSaverOptions.maxNeoMessageLineCount else { return }
        flushEditorLines()
        editorLines.append("")
        linesTableView.reloadData()
        refreshLinesSection()
        let newRow = editorLines.count - 1
        linesTableView.scrollRowToVisible(newRow)
        // Begin editing the new cell immediately
        linesTableView.editColumn(1, row: newRow, with: nil, select: true)
    }

    /// Removes the row whose "−" button was tapped.
    @objc private func removeLine(_ sender: NSButton) {
        let row = linesTableView.row(for: sender)
        guard row >= 0, editorLines.count > MatrixScreenSaverOptions.minNeoMessageLineCount else { return }
        flushEditorLines()
        editorLines.remove(at: row)
        linesTableView.reloadData()
        refreshLinesSection()
    }

    /// Resets the editor table to the four default Neo message lines.
    @objc private func resetLines(_ sender: Any?) {
        editorLines = MatrixScreenSaverOptions.defaultNeoMessageLines
        linesTableView.reloadData()
        refreshLinesSection()
    }

    /// Updates button states and resizes the editor window to fit current row count.
    private func refreshLinesSection() {
        let count = editorLines.count
        linesEditorAddButton.isEnabled = count < MatrixScreenSaverOptions.maxNeoMessageLineCount
        // Resize scroll view height to show all rows without a scrollbar
        let tableHeight = CGFloat(count) * (Self.lineRowHeight + linesTableView.intercellSpacing.height)
        if let constraint = linesScrollHeightConstraint {
            constraint.constant = tableHeight
        } else {
            let c = linesScrollView.heightAnchor.constraint(equalToConstant: tableHeight)
            c.isActive = true
            linesScrollHeightConstraint = c
        }
        guard let editor = linesEditorWindow, let contentView = editor.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        if let editorStack = contentView.subviews.first as? NSStackView {
            let fittingSize = editorStack.fittingSize
            let contentSize = NSSize(
                width: ceil(fittingSize.width + editorStack.edgeInsets.right),
                height: ceil(fittingSize.height)
            )
            editor.setContentSize(contentSize)
            editor.contentMinSize = contentSize
        }
    }

    // MARK: – NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { editorLines.count }

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: Self.dragPboardType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: any NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        return dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: any NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let srcStr = info.draggingPasteboard.string(forType: Self.dragPboardType),
              let srcRow = Int(srcStr) else { return false }
        flushEditorLines()
        let item = editorLines.remove(at: srcRow)
        let dest = srcRow < row ? row - 1 : row
        editorLines.insert(item, at: dest)
        tableView.reloadData()
        return true
    }

    // MARK: – NSTableViewDelegate

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let col = tableColumn else { return nil }

        switch col.identifier {
        case Self.handleColumnID:
            let cellView = NSTableCellView()
            let label = NSTextField(labelWithString: "⠿")
            label.font = .systemFont(ofSize: 14)
            label.textColor = .tertiaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
            return cellView

        case Self.textColumnID:
            let identifier = NSUserInterfaceItemIdentifier("lineTextCell")
            let cellView: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self)
                    as? NSTableCellView {
                cellView = reused
            } else {
                cellView = NSTableCellView()
                cellView.identifier = identifier
                let field = NSTextField(string: "")
                field.isEditable = true
                field.isBordered = false
                field.drawsBackground = false
                field.font = .systemFont(ofSize: 13)
                field.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(field)
                cellView.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                    field.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    field.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
            }
            cellView.textField?.stringValue = editorLines[row]
            return cellView

        case Self.removeColumnID:
            let btn = NSButton(title: "−", target: self, action: #selector(removeLine(_:)))
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 13)
            btn.isEnabled = editorLines.count > MatrixScreenSaverOptions.minNeoMessageLineCount
            return btn

        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.lineRowHeight
    }

    /// Builds the scan lines slider row with a live percentage label.
    private func makeScanLinesSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let label = NSTextField(labelWithString: "Scan lines")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)

        scanLinesSlider.target = self
        scanLinesSlider.action = #selector(scanLinesSliderChanged(_:))
        scanLinesSlider.translatesAutoresizingMaskIntoConstraints = false
        scanLinesSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true

        scanLinesValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        scanLinesValueLabel.textColor = .secondaryLabelColor
        scanLinesValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(scanLinesSlider)
        row.addArrangedSubview(scanLinesValueLabel)
        row.addArrangedSubview(scanLinesDirectionPopup)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.scanLinesDescription))
        return stack
    }

    @objc private func scanLinesSliderChanged(_ sender: NSSlider) {
        scanLinesValueLabel.stringValue = "\(Int(sender.doubleValue.rounded()))%"
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

    /// Builds a labeled text input row with its description.
    private func makeTextSection(title: String, field: NSTextField, description: String, fieldWidth: CGFloat? = nil) -> NSView {
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
        field.widthAnchor.constraint(equalToConstant: fieldWidth ?? Self.textFieldWidth).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(field)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(description))
        return stack
    }

     /// Builds the rain duration section with "Run forever" checkbox and optional seconds field.
     private func makeRainDurationSection() -> NSView {
         let stack = NSStackView()
         stack.orientation = .vertical
         stack.alignment = .leading
         stack.spacing = 4
         stack.setHuggingPriority(.required, for: .vertical)

         let checkboxRow = NSStackView()
         checkboxRow.orientation = .horizontal
         checkboxRow.spacing = 0
         checkboxRow.alignment = .centerY
         rainRunForeverCheckbox.setButtonType(.switch)
         checkboxRow.addArrangedSubview(rainRunForeverCheckbox)

         let secondsRow = NSStackView()
         secondsRow.orientation = .horizontal
         secondsRow.spacing = 12
         secondsRow.alignment = .centerY

         let secondsLabel = NSTextField(labelWithString: "Seconds")
         secondsLabel.font = .systemFont(ofSize: 13, weight: .semibold)
         secondsLabel.setContentHuggingPriority(.required, for: .horizontal)

         rainDurationField.alignment = .left
         rainDurationField.controlSize = .regular
         rainDurationField.translatesAutoresizingMaskIntoConstraints = false
         rainDurationField.widthAnchor.constraint(equalToConstant: Self.fourDigitFieldWidth).isActive = true

         secondsRow.addArrangedSubview(secondsLabel)
         secondsRow.addArrangedSubview(rainDurationField)

         stack.addArrangedSubview(checkboxRow)
         stack.addArrangedSubview(secondsRow)
         stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.rainRunForeverDescription))
         stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.rainDurationSecondsDescription))
         return stack
    }

    /// Builds the character size slider with a live size label.
    private func makeCharacterSizeSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let titleLabel = NSTextField(labelWithString: "Character size")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        characterSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        characterSizeSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true

        characterSizeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        characterSizeValueLabel.textColor = .secondaryLabelColor
        characterSizeValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(characterSizeSlider)
        row.addArrangedSubview(characterSizeValueLabel)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.characterSizeDescription))
        return stack
    }

     @objc private func characterSizeSliderChanged(_ sender: NSSlider) {
         let index = Int(sender.doubleValue.rounded())
         let pair = MatrixScreenSaverOptions.characterSizePairs[index]
         characterSizeValueLabel.stringValue = "\(pair.width)×\(pair.height)"
     }

     @objc private func rainRunForeverCheckboxChanged(_ sender: NSButton) {
         let isRunningForever = sender.state == .on
         rainDurationField.isEnabled = !isRunningForever
     }

    /// Builds a titled group box containing a vertical stack of option sections.
    private func makeGroupBox(title: String, views: [NSView]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.contentViewMargins = NSSize(width: 8, height: 8)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setHuggingPriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = box.contentView else { return box }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        return box
    }

    /// Creates the smaller descriptive text used under each option row.
    private func makeDescriptionLabel(_ description: String) -> NSTextField {
        let label = NSTextField(labelWithString: description)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return label
    }

    /// Validates all control values and returns a sanitized options snapshot.
    private func validatedOptions() throws -> MatrixScreenSaverOptions {
        let sizeIndex = Int(characterSizeSlider.doubleValue.rounded())
        let sizePair = MatrixScreenSaverOptions.characterSizePairs[sizeIndex]
         let neoMessageSpeedFactor = try parseDouble(from: neoMessageSpeedFactorField, error: .neoMessageSpeedFactor)
         let rainDensity = try parseDouble(from: rainDensityField, error: .rainDensity)
         let rainDurationSeconds = try parseInteger(from: rainDurationField, error: .rainDurationSeconds)
         let frameRate = try parseDouble(from: frameRateField, error: .frameRate)
        let errorRate = try parseDouble(from: errorRateField, error: .errorRate)

        guard neoMessageSpeedFactor > 0 else {
            throw ValidationError.neoMessageSpeedFactor
        }
         guard rainDensity > 0 else {
             throw ValidationError.rainDensity
         }
         guard rainDurationSeconds >= MatrixScreenSaverOptions.minimumRainDurationSeconds else {
             throw ValidationError.rainDurationSeconds
         }
         guard frameRate > 0, frameRate <= MatrixScreenSaverOptions.maximumFrameRate else {
            throw ValidationError.frameRate
        }
        guard errorRate >= 0 else {
            throw ValidationError.errorRate
        }

        let neoMessageLines = pendingLines.isEmpty ? MatrixScreenSaverOptions.defaultNeoMessageLines : pendingLines

        return MatrixScreenSaverOptions(
            neoMessageSceneEnabled: neoMessageSceneCheckbox.state == .on,
            neoMessageSpeedFactor: neoMessageSpeedFactor,
            neoMessageLines: neoMessageLines,
            numberSceneEnabled: numberSceneCheckbox.state == .on,
            twinkleEnabled: twinkleCheckbox.state == .on,
            diffuseEnabled: diffuseCheckbox.state == .on,
            characterWidth: sizePair.width,
            characterHeight: sizePair.height,
             rainDensity: rainDensity,
             rainRunForever: rainRunForeverCheckbox.state == .on,
             rainDurationSeconds: rainDurationSeconds,
             frameRate: frameRate,
            errorRate: errorRate,
            characters: charactersField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            scanLinesIntensity: scanLinesSlider.doubleValue / 100,
            scanLinesVertical: scanLinesDirectionPopup.indexOfSelectedItem == 0
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
        let normalized = Self.normalizedDecimalText(fieldEditor.string)
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
            width: ceil(fittingSize.width),
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

    private static let textFieldWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidth = ceil(("MMMMMMMMMMMMMMMMMMMMMMMM" as NSString).size(withAttributes: [.font: font]).width)
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
