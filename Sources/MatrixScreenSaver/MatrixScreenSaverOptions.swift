import AppKit
import CoreText
import ScreenSaver

struct MatrixScreenSaverOptions: Equatable {
    private enum Keys {
        static let neoMessageSceneEnabled = "NeoMessageSceneEnabled"
        static let neoMessageSpeedFactor = "NeoMessageSpeedFactor"
        static let name = "Name"
        static let neoMessageLines = "NeoMessageLines"
        static let cmdSceneEnabled = "CmdSceneEnabled"
        /// Separate key so the retired custom speed cannot become an output hold.
        static let cmdOutputHoldSeconds = "CmdOutputHoldSeconds"
        static let commands = "Commands"
        /// Preserves random playback for installations without a stored mode.
        static let commandsRunInSequence = "CommandsRunInSequence"
        /// Optional shuffle for whole-list playback; absent preserves the saved order.
        static let commandsShuffleSequence = "CommandsShuffleSequence"
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
        /// Defaults key for the selected rain font families.
        static let rainFonts = "RainFonts"
        /// Independent of custom characters and fonts so switching presets preserves both.
        static let rainGlyphSet = "RainGlyphSet"
        static let scanLinesIntensity = "ScanLinesIntensity"
        static let scanLinesVertical = "ScanLinesVertical"
    }

    static let defaultNeoMessageSceneEnabled = true
    static let defaultNeoMessageSpeedFactor = 1.0
    static let defaultName = ""
    static let defaultNeoMessageLines: [String] = []
    static let defaultCmdSceneEnabled = false
    /// Post-exit reading time for each custom command.
    static let defaultCmdOutputHoldSeconds = 10.0
    static let defaultCommands: [String] = []
    /// Existing installations continue choosing one random command.
    static let defaultCommandsRunInSequence = false
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
     static let maxCommandCount = 20
     static let maxCommandLength = 512

    static let neoMessageSceneDescription = "Show the Neo message intro. On by default."
    static let neoMessageSpeedFactorDescription = "Typing speed multiplier for Neo, custom commands and trace program. Default: 1.0."
    /// Output is immediate; this delay only starts after command completion.
    static let cmdOutputHoldSecondsDescription = "Seconds to keep output visible after the command finishes. 0 advances immediately. Default: 10."
    static let nameDescription = "Name used in the intro message (\"Wake up, {name}...\"). Empty = Neo."
    static let neoMessageLinesDescription = "Lines typed during the Neo message intro (0–10, max 256 chars). Leave empty to use the Name-based default message."
    static let cmdSceneDescription = "Execute custom commands and show its output as messages. Off by default."
    /// Retained in the editor where users enter commands that execute with host permissions.
    static let commandsSecurityWarning = "Commands run with the host's permissions; commands and output are visible even while the screen is locked."
    static let commandsDescription = "One shell command per row (up to 20, 512 characters each). Drag rows to change execution order. Overlong commands are ignored. Empty disables the scene."
    static let numberSceneDescription = "Show the trace program intro. On by default."
    static let diffuseDescription = "On by default."
    static let twinkleDescription = "On by default."
    static let characterSizeDescription = "Character cell size in pixels. Default: 16×30."

    static let characterSizePairs: [(width: Int, height: Int)] = [
        (8, 15), (9, 17), (10, 19), (11, 21), (12, 23), (13, 24), (14, 26), (15, 28), (16, 30), (17, 32), (18, 34), (19, 36), (20, 38), (21, 40), (22, 42), (23, 44), (24, 46)
    ]
    static let defaultCharacterSizeIndex = 8
     static let rainDensityDescription = "Rain density multiplier. Default: 1.0."
     static let rainDurationSecondsDescription = "How long rain keeps starting new falling lines (1–9999 seconds) before it winds down. Default: 300 (5 minutes)."
     static let frameRateDescription = "Target frame rate in fps, 1–1000. Default: 25."
    static let errorRateDescription = "Character change rate factor. Default: 1.0."
    static let charactersDescription = "Custom glyph set (e.g. ATGC). Empty = default."
    /// Help text shown under the Font picker.
    static let rainFontsDescription = "Choose a font for the default glyph set."
    /// Default selection: no fonts, which keeps the built-in glyphs and system font.
    static let defaultRainFonts: [String] = []
    static let scanLinesDescription = "CRT scan line intensity (0–100%). Default: 25%."

    var neoMessageSceneEnabled = defaultNeoMessageSceneEnabled
    var neoMessageSpeedFactor = defaultNeoMessageSpeedFactor
    var name = defaultName
    var neoMessageLines = defaultNeoMessageLines
    var cmdSceneEnabled = defaultCmdSceneEnabled
    /// Seconds to keep completed output visible before the next command or scene.
    var cmdOutputHoldSeconds = defaultCmdOutputHoldSeconds
    var commands = defaultCommands
    /// Whether each scene entry runs the whole command list in order.
    var commandsRunInSequence = defaultCommandsRunInSequence
    /// Shuffles whole-list playback once per scene cycle using the shared display seed.
    var commandsShuffleSequence = false
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
    /// Zero or one selected font; the array format preserves existing saved preferences.
    var rainFonts = defaultRainFonts
    /// Bundled film glyphs or the existing configurable rain repertoire.
    var rainGlyphSet: RainGlyphSet = .default
    var scanLinesIntensity = defaultScanLinesIntensity
    var scanLinesVertical = defaultScanLinesVertical

    /// Identifies changes that rebuild the grid or alter the coordinated scene sequence.
    ///
    /// - Parameter previous: Configuration currently applied to the session.
    /// - Returns: Whether all displays must restart together rather than update in place.
    func requiresSceneRestart(comparedTo previous: MatrixScreenSaverOptions) -> Bool {
        characterWidth != previous.characterWidth || characterHeight != previous.characterHeight ||
        neoMessageSceneEnabled != previous.neoMessageSceneEnabled ||
        neoMessageSpeedFactor != previous.neoMessageSpeedFactor || neoMessageLines != previous.neoMessageLines ||
        (neoMessageLines.isEmpty && name != previous.name) ||
        cmdSceneEnabled != previous.cmdSceneEnabled || commands != previous.commands ||
        cmdOutputHoldSeconds != previous.cmdOutputHoldSeconds ||
        commandsRunInSequence != previous.commandsRunInSequence ||
        commandsShuffleSequence != previous.commandsShuffleSequence ||
        numberSceneEnabled != previous.numberSceneEnabled ||
        rainRunForever != previous.rainRunForever || rainDurationSeconds != previous.rainDurationSeconds
    }

    /// Converts persisted options into the renderer configuration type.
    func rendererConfiguration(isPreview: Bool = false) -> NativeMatrixRenderer.Configuration {
        NativeMatrixRenderer.Configuration(
            neoMessageSceneEnabled: neoMessageSceneEnabled,
            neoMessageSpeedFactor: neoMessageSpeedFactor,
            cmdSceneEnabled: cmdSceneEnabled,
            cmdOutputHoldSeconds: cmdOutputHoldSeconds,
            commands: commands,
            commandsRunInSequence: commandsRunInSequence,
            commandsShuffleSequence: commandsShuffleSequence,
            numberSceneEnabled: numberSceneEnabled,
            twinkleEnabled: twinkleEnabled,
            diffuseEnabled: diffuseEnabled,
            rainDensity: rainDensity,
             rainRunForever: rainRunForever,
             rainDurationSeconds: rainDurationSeconds,
             frameRate: frameRate,
            errorRate: errorRate,
            characters: characters,
            rainFonts: Array(rainFonts.prefix(1)),
            rainGlyphSet: rainGlyphSet,
            neoMessageName: name,
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
            return Array(result.prefix(Self.maxNeoMessageLineCount))
        }()
        let sanitizedCommands: [String] = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Clipping shell text can change which files or actions a command targets.
            .filter { !$0.isEmpty && $0.count <= Self.maxCommandLength && !$0.utf8.contains(0) }
            .prefix(Self.maxCommandCount)
            .map { $0 }
        return MatrixScreenSaverOptions(
            neoMessageSceneEnabled: neoMessageSceneEnabled,
            neoMessageSpeedFactor: max(neoMessageSpeedFactor, Self.minimumNeoMessageSpeedFactor),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            neoMessageLines: sanitizedLines,
            cmdSceneEnabled: cmdSceneEnabled,
            cmdOutputHoldSeconds: cmdOutputHoldSeconds.isFinite && cmdOutputHoldSeconds >= 0 ? cmdOutputHoldSeconds : Self.defaultCmdOutputHoldSeconds,
            commands: sanitizedCommands,
            commandsRunInSequence: commandsRunInSequence,
            commandsShuffleSequence: commandsShuffleSequence,
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
            rainFonts: Array(rainFonts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(1)),
            rainGlyphSet: rainGlyphSet,
            scanLinesIntensity: max(0, min(1, scanLinesIntensity)),
            scanLinesVertical: scanLinesVertical
        )
    }

    /// Registers the default option values with the screen saver defaults store.
    static func registerDefaults(in defaults: ScreenSaverDefaults) {
        defaults.register(defaults: [
            Keys.neoMessageSceneEnabled: defaultNeoMessageSceneEnabled,
            Keys.neoMessageSpeedFactor: defaultNeoMessageSpeedFactor,
            Keys.name: defaultName,
            Keys.neoMessageLines: defaultNeoMessageLines,
            Keys.cmdSceneEnabled: defaultCmdSceneEnabled,
            Keys.cmdOutputHoldSeconds: defaultCmdOutputHoldSeconds,
            Keys.commands: defaultCommands,
            Keys.commandsRunInSequence: defaultCommandsRunInSequence,
            Keys.commandsShuffleSequence: false,
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
            Keys.rainFonts: defaultRainFonts,
            Keys.rainGlyphSet: RainGlyphSet.default.rawValue,
            Keys.scanLinesIntensity: defaultScanLinesIntensity,
            Keys.scanLinesVertical: defaultScanLinesVertical,
        ])
    }

    /// Loads the persisted options from the screen saver defaults store.
    static func load(from defaults: ScreenSaverDefaults) -> MatrixScreenSaverOptions {
        MatrixScreenSaverOptions(
            neoMessageSceneEnabled: defaults.bool(forKey: Keys.neoMessageSceneEnabled),
            neoMessageSpeedFactor: defaults.double(forKey: Keys.neoMessageSpeedFactor),
            name: defaults.string(forKey: Keys.name) ?? defaultName,
            neoMessageLines: (defaults.array(forKey: Keys.neoMessageLines) as? [String]) ?? defaultNeoMessageLines,
            cmdSceneEnabled: defaults.bool(forKey: Keys.cmdSceneEnabled),
            cmdOutputHoldSeconds: defaults.double(forKey: Keys.cmdOutputHoldSeconds),
            commands: (defaults.array(forKey: Keys.commands) as? [String]) ?? defaultCommands,
            commandsRunInSequence: defaults.bool(forKey: Keys.commandsRunInSequence),
            commandsShuffleSequence: defaults.bool(forKey: Keys.commandsShuffleSequence),
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
            rainFonts: (defaults.array(forKey: Keys.rainFonts) as? [String]) ?? defaultRainFonts,
            rainGlyphSet: RainGlyphSet(rawValue: defaults.string(forKey: Keys.rainGlyphSet) ?? "") ?? .default,
            scanLinesIntensity: defaults.double(forKey: Keys.scanLinesIntensity),
            scanLinesVertical: defaults.bool(forKey: Keys.scanLinesVertical)
        ).sanitized()
    }

    /// Saves the current options back to the screen saver defaults store.
    func save(to defaults: ScreenSaverDefaults) {
        let options = sanitized()
        defaults.set(options.neoMessageSceneEnabled, forKey: Keys.neoMessageSceneEnabled)
        defaults.set(options.neoMessageSpeedFactor, forKey: Keys.neoMessageSpeedFactor)
        defaults.set(options.name, forKey: Keys.name)
        defaults.set(options.neoMessageLines, forKey: Keys.neoMessageLines)
        defaults.set(options.cmdSceneEnabled, forKey: Keys.cmdSceneEnabled)
        defaults.set(options.cmdOutputHoldSeconds, forKey: Keys.cmdOutputHoldSeconds)
        defaults.set(options.commands, forKey: Keys.commands)
        defaults.set(options.commandsRunInSequence, forKey: Keys.commandsRunInSequence)
        defaults.set(options.commandsShuffleSequence, forKey: Keys.commandsShuffleSequence)
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
        defaults.set(options.rainFonts, forKey: Keys.rainFonts)
        defaults.set(options.rainGlyphSet.rawValue, forKey: Keys.rainGlyphSet)
        defaults.set(options.scanLinesIntensity, forKey: Keys.scanLinesIntensity)
        defaults.set(options.scanLinesVertical, forKey: Keys.scanLinesVertical)
        defaults.synchronize()
    }
}

/// A top-origin document keeps the Rain options at the top when its content grows.
private final class RainOptionsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class MatrixScreenSaverOptionsSheetController: NSObject,
    NSTextFieldDelegate, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
     private enum ValidationError: LocalizedError {
         case neoMessageSpeedFactor
          case cmdOutputHoldSeconds
          case rainDensity
           case frameRate
           case errorRate
           case rainDurationSeconds

         var errorDescription: String? {
             switch self {
             case .neoMessageSpeedFactor:
                  return "Intro typing speed must be a positive number."
             case .cmdOutputHoldSeconds:
                  return "Output hold must be a finite non-negative number of seconds."
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

    /// Delivers validated options to either the saver view or the wallpaper host.
    private let onApply: (MatrixScreenSaverOptions) -> Void
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let rootStack = NSStackView()
    private let neoMessageSceneCheckbox = NSButton(checkboxWithTitle: "Show Neo message scene", target: nil, action: nil)
    private let neoMessageSpeedFactorField = NSTextField(string: "")
    private let cmdOutputHoldSecondsField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
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
    /// The shared list edits only one scene's pending values at a time.
    private var editingCommands = false
    /// Describes the active list's limits without sharing its persisted values.
    private var editorDescriptionLabel: NSTextField?
    /// Shell warning shown only while editing executable commands.
    private var editorSecurityWarning: NSTextField?
    /// Neo-only reset action hidden when editing commands.
    private let resetLinesButton = NSButton(title: "Reset lines", target: nil, action: nil)
    /// Commands may be empty; Neo retains at least one editable row.
    private var minimumEditorRows: Int { editingCommands ? 0 : MatrixScreenSaverOptions.minNeoMessageLineCount }
    /// Applies each scene's existing storage limit to the shared list.
    private var maximumEditorRows: Int {
        editingCommands ? MatrixScreenSaverOptions.maxCommandCount : MatrixScreenSaverOptions.maxNeoMessageLineCount
    }
    private let cmdSceneCheckbox = NSButton(checkboxWithTitle: "Show custom scene", target: nil, action: nil)
    /// Scene-owned editor buttons remain available only while their scene is enabled.
    private let commandsEditButton = NSButton(title: "Edit…", target: nil, action: nil)
    private let linesEditButton = NSButton(title: "Edit…", target: nil, action: nil)
    /// Radio controls share an action and parent so AppKit treats them as one group.
    private let commandsSequenceRadio = NSButton(radioButtonWithTitle: "In sequence", target: nil, action: nil)
    /// Selects a single command on every scene entry.
    private let commandsRandomRadio = NSButton(radioButtonWithTitle: "One random command", target: nil, action: nil)
    /// Runs the complete list in a newly shuffled order for each cycle.
    private let commandsShuffleRadio = NSButton(radioButtonWithTitle: "All commands in random order", target: nil, action: nil)
    /// Commands accepted in the editor, not persisted until the main dialog is accepted.
    private var pendingCommands: [String] = []
    private let numberSceneCheckbox = NSButton(checkboxWithTitle: "Show trace program scene", target: nil, action: nil)
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
    /// Pull-down listing installed fonts with one selected entry.
    private let rainFontsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let rainFontsResetButton = NSButton(title: "Reset", target: nil, action: nil)
    /// Radio buttons share a parent and action for native keyboard navigation.
    private let rainGlyphRadios = RainGlyphSet.allCases.map { NSButton(radioButtonWithTitle: $0.title, target: nil, action: nil) }
    /// Wrapping native text uses the same font fallback as the renderer.
    private let rainGlyphPreview = NSTextField(wrappingLabelWithString: "")
    private var selectedRainGlyphSet: RainGlyphSet = .default
    /// Zero or one selected font, kept in the persisted array format.
    private var selectedRainFonts: [String] = []
    private var didClose = false

    /// Creates native options UI with a host-owned apply action.
    ///
    /// - Parameter onApply: Receives validated options when the user chooses Apply.
    init(onApply: @escaping (MatrixScreenSaverOptions) -> Void) {
        self.onApply = onApply
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
        cmdOutputHoldSecondsField.stringValue = Self.format(options.cmdOutputHoldSeconds)
        nameField.stringValue = options.name
        pendingLines = options.neoMessageLines
        cmdSceneCheckbox.state = options.cmdSceneEnabled ? .on : .off
        pendingCommands = options.commands
        commandsSequenceRadio.state = options.commandsRunInSequence && !options.commandsShuffleSequence ? .on : .off
        commandsRandomRadio.state = options.commandsRunInSequence ? .off : .on
        commandsShuffleRadio.state = options.commandsRunInSequence && options.commandsShuffleSequence ? .on : .off
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
        selectedRainFonts = options.sanitized().rainFonts
        selectedRainGlyphSet = options.rainGlyphSet
        updateRainGlyphControls()
        rebuildRainFontsMenu()
        updateSceneControls()
        sizeWindowToFitContent()
    }

    /// Returns the native sheet window presented by ScreenSaver.framework.
    func configureSheet() -> NSWindow {
        window
    }

    /// Validates and applies the edited options.
    @objc private func apply(_ sender: Any?) {
        do {
            let options = try validatedOptions()
            onApply(options)
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

    /// Opens the project's donation page in the default browser.
    @objc private func openDonationPage(_ sender: Any?) {
        if let url = URL(string: "https://www.buymeacoffee.com/yesman82") {
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
        window.title = "Matrix Screen Saver and animated Wallpaper"
        window.isReleasedWhenClosed = false
        window.delegate = self

         characterSizeSlider.target = self
         characterSizeSlider.action = #selector(characterSizeSliderChanged(_:))
         neoMessageSpeedFactorField.formatter = Self.numberFormatter
         cmdOutputHoldSecondsField.formatter = Self.numberFormatter
         cmdOutputHoldSecondsField.delegate = self
         rainDensityField.formatter = Self.numberFormatter
         rainDurationField.formatter = Self.integerFormatter
         frameRateField.formatter = Self.numberFormatter
         errorRateField.formatter = Self.numberFormatter
         neoMessageSpeedFactorField.delegate = self
         rainDensityField.delegate = self
         rainDurationField.delegate = self
         frameRateField.delegate = self
          errorRateField.delegate = self
          charactersField.delegate = self
         rainRunForeverCheckbox.target = self
         rainRunForeverCheckbox.action = #selector(rainRunForeverCheckboxChanged(_:))
        for checkbox in [neoMessageSceneCheckbox, cmdSceneCheckbox, numberSceneCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(sceneCheckboxChanged(_:))
        }

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let aboutButton = NSButton(title: "About", target: self, action: #selector(openRepository(_:)))
        aboutButton.bezelStyle = .inline
        aboutButton.isBordered = false
        aboutButton.contentTintColor = .linkColor
        aboutButton.font = .systemFont(ofSize: 13)

        // Tab pages lay out during insertion, before Auto Layout sizes the tab view.
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(makeOptionsTab(title: "General", views: [
            makeCharacterSizeSection(),
            makeScanLinesSection(),
            makeNumericSection(title: "Frame rate", field: frameRateField, description: MatrixScreenSaverOptions.frameRateDescription),
        ]))
        tabs.addTabViewItem(makeOptionsTab(title: "Intro scenes", views: [
            makeSceneGroup(views: [
                makeCheckboxSection(checkbox: neoMessageSceneCheckbox, description: MatrixScreenSaverOptions.neoMessageSceneDescription),
                makeTextSection(title: "Name", field: nameField, description: MatrixScreenSaverOptions.nameDescription, fieldWidth: Self.textFieldWidth / 2),
                makeNeoMessageLinesButtonRow(),
            ]),
            makeSceneGroup(views: [makeCustomShellCommandsSection()]),
            makeSceneGroup(views: [makeCheckboxSection(checkbox: numberSceneCheckbox, description: MatrixScreenSaverOptions.numberSceneDescription)]),
            makeNumericSection(title: "Typing speed", field: neoMessageSpeedFactorField, description: MatrixScreenSaverOptions.neoMessageSpeedFactorDescription),
        ]))
        tabs.addTabViewItem(makeOptionsTab(title: "Rain", views: [
             makeCheckboxSection(checkbox: twinkleCheckbox, description: MatrixScreenSaverOptions.twinkleDescription),
             makeCheckboxSection(checkbox: diffuseCheckbox, description: MatrixScreenSaverOptions.diffuseDescription),
             makeNumericSection(title: "Density", field: rainDensityField, description: MatrixScreenSaverOptions.rainDensityDescription),
              makeRainDurationSection(),
              makeRainGlyphSection(),
              makeRainFontsSection(),
             makeTextSection(title: "Characters", field: charactersField, description: MatrixScreenSaverOptions.charactersDescription, fieldWidth: Self.textFieldWidth / 2),
             makeNumericSection(title: "Error rate", field: errorRateField, description: MatrixScreenSaverOptions.errorRateDescription),
        ]))
        rootStack.addArrangedSubview(tabs)

        let groupWidth = -(rootStack.edgeInsets.left + rootStack.edgeInsets.right)
        // Keep every page the same size so switching tabs never moves the dialog buttons.
        NSLayoutConstraint.activate([
            tabs.widthAnchor.constraint(equalToConstant: 520),
            tabs.heightAnchor.constraint(equalToConstant: 550),
            tabs.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: groupWidth),
        ])

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

        let versionString = Bundle(for: MatrixScreenSaverOptionsSheetController.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: versionString.isEmpty ? "" : "v\(versionString)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)

        let coffeeButton = NSButton(title: "Buy me a coffee ☕", target: self, action: #selector(openDonationPage(_:)))
        coffeeButton.bezelStyle = .inline
        coffeeButton.isBordered = false
        coffeeButton.controlSize = .small
        coffeeButton.contentTintColor = .linkColor
        coffeeButton.font = aboutButton.font
        coffeeButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacerRight = NSView()
        spacerRight.translatesAutoresizingMaskIntoConstraints = false
        spacerRight.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerRight.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        footer.addArrangedSubview(resetButton)
        footer.addArrangedSubview(aboutButton)
        footer.addArrangedSubview(versionLabel)
        footer.addArrangedSubview(coffeeButton)
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
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        sizeWindowToFitContent()
    }

    /// Wraps scene controls in a native, untitled fieldset without changing their actions.
    private func makeSceneGroup(views: [NSView]) -> NSBox {
        let box = NSBox()
        box.titlePosition = .noTitle
        box.contentViewMargins = NSSize(width: 8, height: 8)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = box.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return box
    }

    /// Refreshes editable controls without changing the scene's retained values or enable toggle.
    private func updateSceneControls() {
        cmdOutputHoldSecondsField.isEnabled = cmdSceneCheckbox.state == .on
        nameField.isEnabled = neoMessageSceneCheckbox.state == .on
        linesEditButton.isEnabled = neoMessageSceneCheckbox.state == .on
        for control in [commandsEditButton, commandsSequenceRadio, commandsRandomRadio, commandsShuffleRadio] {
            control.isEnabled = cmdSceneCheckbox.state == .on
        }
    }

    /// Keeps fieldset enablement in sync with the scene toggles.
    @objc private func sceneCheckboxChanged(_ sender: NSButton) {
        updateSceneControls()
    }

    /// Groups shell command controls at their position in the intro sequence.
    private func makeCustomShellCommandsSection() -> NSView {
        commandsEditButton.target = self
        commandsEditButton.action = #selector(editCommands(_:))
        commandsEditButton.setAccessibilityLabel("Edit custom shell commands")
        let label = NSTextField(labelWithString: "Commands")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let heading = NSStackView(views: [label, commandsEditButton])
        heading.spacing = 12
        for radio in [commandsSequenceRadio, commandsRandomRadio, commandsShuffleRadio] {
            radio.target = self
            radio.action = #selector(commandModeChanged(_:))
        }
        let modes = NSStackView(views: [commandsSequenceRadio, commandsRandomRadio, commandsShuffleRadio])
        modes.orientation = .vertical
        modes.alignment = .leading
        modes.spacing = 4
        let stack = NSStackView(views: [
            makeCheckboxSection(checkbox: cmdSceneCheckbox, description: MatrixScreenSaverOptions.cmdSceneDescription),
            heading, modes,
            makeNumericSection(title: "Output hold", field: cmdOutputHoldSecondsField,
                               description: MatrixScreenSaverOptions.cmdOutputHoldSecondsDescription),
        ])
        cmdOutputHoldSecondsField.setAccessibilityLabel("Command output hold in seconds")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    /// Keeps the command playback choices mutually exclusive.
    @objc private func commandModeChanged(_ sender: NSButton) {
        commandsSequenceRadio.state = sender === commandsSequenceRadio ? .on : .off
        commandsRandomRadio.state = sender === commandsRandomRadio ? .on : .off
        commandsShuffleRadio.state = sender === commandsShuffleRadio ? .on : .off
    }

    /// Opens a separate editor without changing the commands accepted by the main dialog.
    @objc private func editCommands(_ sender: Any?) {
        editingCommands = true
        openListEditor()
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
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true

        linesEditButton.target = self
        linesEditButton.action = #selector(editLines(_:))
        linesEditButton.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(linesEditButton)

        stack.addArrangedSubview(row)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.neoMessageLinesDescription))
        return stack
    }

    /// Builds the shared, reorderable scene list editor presented as a sheet.
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

        resetLinesButton.target = self
        resetLinesButton.action = #selector(resetLines(_:))
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
        let description = makeDescriptionLabel("")
        let warning = makeDescriptionLabel(MatrixScreenSaverOptions.commandsSecurityWarning)
        editorDescriptionLabel = description
        editorSecurityWarning = warning
        editorStack.addArrangedSubview(description)
        editorStack.addArrangedSubview(warning)
        editorStack.addArrangedSubview(footer)

        linesScrollView.widthAnchor.constraint(equalTo: editorStack.widthAnchor,
            constant: -(editorStack.edgeInsets.left + editorStack.edgeInsets.right)).isActive = true
        footer.widthAnchor.constraint(equalTo: editorStack.widthAnchor,
            constant: -(editorStack.edgeInsets.left + editorStack.edgeInsets.right)).isActive = true
        for label in [description, warning] {
            label.widthAnchor.constraint(equalTo: linesScrollView.widthAnchor).isActive = true
        }
        linesScrollView.widthAnchor.constraint(equalToConstant: 460).isActive = true

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
        editingCommands = false
        openListEditor()
    }

    /// Loads the selected scene's values without committing edits from the previous sheet.
    private func openListEditor() {
        let editor = linesEditorWindow ?? buildLinesEditorWindow()
        linesEditorWindow = editor
        editor.title = editingCommands ? "Custom Shell Commands" : "Neo Message Lines"
        editorDescriptionLabel?.stringValue = editingCommands
            ? MatrixScreenSaverOptions.commandsDescription : MatrixScreenSaverOptions.neoMessageLinesDescription
        editorSecurityWarning?.isHidden = !editingCommands
        resetLinesButton.isHidden = editingCommands
        linesTableView.setAccessibilityLabel(editingCommands ? "Custom commands" : "Neo message lines")
        linesEditorAddButton.setAccessibilityLabel(editingCommands ? "Add command" : "Add message")
        editorLines = editingCommands ? pendingCommands : pendingLines
        linesTableView.reloadData()
        refreshLinesSection()
        window.beginSheet(editor)
    }

    /// Commits the editor lines and closes the editor sheet.
    @objc private func applyLines(_ sender: Any?) {
        linesEditorWindow?.makeFirstResponder(nil)
        flushEditorLines()
        if editingCommands {
            // Never truncate shell syntax into a different executable command; sanitize on main Apply.
            pendingCommands = editorLines
        } else {
            pendingLines = editorLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { String($0.prefix(MatrixScreenSaverOptions.maxNeoMessageLineLength)) }
        }
        window.endSheet(linesEditorWindow ?? window)
    }

    /// Discards editor changes and closes the editor sheet.
    @objc private func cancelLines(_ sender: Any?) {
        linesEditorWindow?.makeFirstResponder(nil)
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
        guard editorLines.count < maximumEditorRows else { return }
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
        guard row >= 0, editorLines.count > minimumEditorRows else { return }
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
        linesEditorAddButton.isEnabled = count < maximumEditorRows
        linesScrollView.hasVerticalScroller = count > 10
        let tableHeight = CGFloat(max(1, min(count, 10))) * (Self.lineRowHeight + linesTableView.intercellSpacing.height)
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
        return info.draggingSource as? NSTableView === tableView && dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: any NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSource as? NSTableView === tableView, dropOperation == .above,
              let srcStr = info.draggingPasteboard.string(forType: Self.dragPboardType),
              let srcRow = Int(srcStr), editorLines.indices.contains(srcRow),
              (0...editorLines.count).contains(row) else { return false }
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
                field.delegate = self
                field.isBordered = false
                field.drawsBackground = false
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
            cellView.textField?.font = editingCommands ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
            cellView.textField?.setAccessibilityLabel(editingCommands ? "Command \(row + 1)" : "Message \(row + 1)")
            return cellView

        case Self.removeColumnID:
            let btn = NSButton(title: "−", target: self, action: #selector(removeLine(_:)))
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 13)
            btn.isEnabled = editorLines.count > minimumEditorRows
            btn.setAccessibilityLabel(editingCommands ? "Remove command \(row + 1)" : "Remove message \(row + 1)")
            return btn

        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.lineRowHeight
    }

    /// Saves edits before scrolling recycles a row's text field.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === charactersField {
            updateRainGlyphPreview()
            return
        }
        let row = linesTableView.row(for: field)
        guard editorLines.indices.contains(row) else { return }
        editorLines[row] = field.stringValue
    }

    /// Prevents AppKit's text substitutions from rewriting executable shell syntax.
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard editingCommands, let field = notification.object as? NSTextField,
              let editor = field.currentEditor() as? NSTextView else { return }
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
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
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        scanLinesSlider.setAccessibilityLabel("Scan line intensity")
        scanLinesDirectionPopup.setAccessibilityLabel("Scan line direction")

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
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        field.setAccessibilityLabel(title)

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

    private func makeRainGlyphSection() -> NSView {
        let heading = NSTextField(labelWithString: "Glyph set")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        for (index, radio) in rainGlyphRadios.enumerated() {
            radio.tag = index
            radio.target = self
            radio.action = #selector(rainGlyphSetChanged(_:))
        }
        let row = NSStackView(views: rainGlyphRadios)
        row.spacing = 12
        rainGlyphPreview.drawsBackground = true
        rainGlyphPreview.backgroundColor = .black
        rainGlyphPreview.textColor = .green
        rainGlyphPreview.lineBreakMode = .byCharWrapping
        rainGlyphPreview.maximumNumberOfLines = 0
        rainGlyphPreview.setAccessibilityLabel("Selected rain glyphs")
        let stack = NSStackView(views: [heading, row, rainGlyphPreview])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)
        rainGlyphPreview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        row.toolTip = "Classic and Resurrections use their original bundled fonts. Default uses the settings below."
        return stack
    }

    @objc private func rainGlyphSetChanged(_ sender: NSButton) {
        selectedRainGlyphSet = RainGlyphSet.allCases[sender.tag]
        updateRainGlyphControls()
    }

    /// Film glyphs require their matching font, so custom settings remain saved but inactive.
    private func updateRainGlyphControls() {
        for (preset, radio) in zip(RainGlyphSet.allCases, rainGlyphRadios) {
            radio.state = preset == selectedRainGlyphSet ? .on : .off
        }
        let customEnabled = selectedRainGlyphSet == .default
        rainFontsButton.isEnabled = customEnabled
        rainFontsResetButton.isEnabled = customEnabled
        charactersField.isEnabled = customEnabled
        updateRainGlyphPreview()
    }

    /// Reads the renderer's actual repertoire so custom filtering and preset weighting stay consistent.
    private func updateRainGlyphPreview() {
        var options = MatrixScreenSaverOptions()
        options.rainGlyphSet = selectedRainGlyphSet
        options.rainFonts = selectedRainFonts
        options.characters = charactersField.stringValue
        let renderer = NativeMatrixRenderer()
        renderer.updateConfiguration(options.sanitized().rendererConfiguration())
        let name = renderer.activeRainFonts.first
        rainGlyphPreview.font = name.flatMap { RainFontCatalog.font(named: $0, size: 12) }
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        rainGlyphPreview.stringValue = String(String.UnicodeScalarView(renderer.rainGlyphs))
        rainGlyphPreview.invalidateIntrinsicContentSize()
    }

    /// Builds the rain fonts picker with every discovered font family.
    private func makeRainFontsSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)

        let heading = NSTextField(labelWithString: "Font")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        rainFontsButton.setAccessibilityLabel("Font")
        rainFontsButton.translatesAutoresizingMaskIntoConstraints = false
        rainFontsButton.widthAnchor.constraint(equalToConstant: Self.textFieldWidth).isActive = true
        (rainFontsButton.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail

        let resetButton = rainFontsResetButton
        resetButton.target = self
        resetButton.action = #selector(clearRainFonts(_:))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        resetButton.setAccessibilityLabel("Reset font to system default")
        resetButton.toolTip = "Use the default system font"
        let row = NSStackView(views: [rainFontsButton, resetButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(makeDescriptionLabel(MatrixScreenSaverOptions.rainFontsDescription))
        stack.addArrangedSubview(row)
        stack.setCustomSpacing(8, after: stack.arrangedSubviews[1])
        return stack
    }

    /// Rebuilds the full font menu with the current selection.
    private func rebuildRainFontsMenu() {
        let menu = NSMenu()
        let systemFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        // Resolve the backing family instead of exposing the system alias or face weights.
        let backingFont = CTFontCreateWithGraphicsFont(CTFontCopyGraphicsFont(systemFont, nil), 16, nil, nil)
        let defaultTitle = "Default - \(CTFontCopyFamilyName(backingFont))"
        let summary = selectedRainFonts.first ?? defaultTitle
        menu.addItem(NSMenuItem(title: summary, action: nil, keyEquivalent: ""))

        let defaultItem = NSMenuItem(title: defaultTitle, action: #selector(clearRainFonts(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.state = selectedRainFonts.isEmpty ? .on : .off
        menu.addItem(defaultItem)
        menu.addItem(.separator())

        let families = RainFontCatalog.families(alwaysInclude: selectedRainFonts)
        for family in families {
            let item = NSMenuItem(title: family, action: #selector(selectRainFont(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = family
            item.state = selectedRainFonts.contains(family) ? .on : .off
            menu.addItem(item)
        }
        rainFontsButton.menu = menu
        rainFontsButton.selectItem(at: 0)
    }

    /// Replaces the selected font without toggling an already selected font off.
    @objc private func selectRainFont(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? String else { return }
        selectedRainFonts = [family]
        rebuildRainFontsMenu()
        updateRainGlyphPreview()
    }

    /// Clears the selection so the built-in glyphs and system font are used.
    @objc private func clearRainFonts(_ sender: Any?) {
        selectedRainFonts = []
        rebuildRainFontsMenu()
        updateRainGlyphPreview()
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
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        field.setAccessibilityLabel(title)

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
         secondsLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
         rainDurationField.setAccessibilityLabel("Rain duration in seconds")

         rainDurationField.alignment = .left
         rainDurationField.controlSize = .regular
         rainDurationField.translatesAutoresizingMaskIntoConstraints = false
         rainDurationField.widthAnchor.constraint(equalToConstant: Self.fourDigitFieldWidth).isActive = true

         secondsRow.addArrangedSubview(secondsLabel)
         secondsRow.addArrangedSubview(rainDurationField)

         stack.addArrangedSubview(checkboxRow)
         stack.addArrangedSubview(secondsRow)
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
        titleLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        characterSizeSlider.setAccessibilityLabel("Character size")

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

    /// Builds a top-aligned tab page with full-width sections so help text wraps within the page.
    private func makeOptionsTab(title: String, views: [NSView]) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        // Start at the real page size so NSTabView never lays the page out at its 20pt placeholder width,
        // which made the fixed-width rows report unsatisfiable constraints in the screen saver host.
        let frame = NSRect(x: 0, y: 0, width: 520, height: 550)
        let scrolls = title == "Rain"
        let contentView = scrolls ? RainOptionsDocumentView(frame: frame) : NSView(frame: frame)
        if scrolls {
            let scrollView = NSScrollView(frame: frame)
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.documentView = contentView
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
            item.view = scrollView
        } else {
            item.view = contentView
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setHuggingPriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrolls ? stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
                : stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
        ])
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return item
    }

    /// Creates the smaller descriptive text used under each option row.
    private func makeDescriptionLabel(_ description: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: description)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// Validates all control values and returns a sanitized options snapshot.
    private func validatedOptions() throws -> MatrixScreenSaverOptions {
        let sizeIndex = Int(characterSizeSlider.doubleValue.rounded())
        let sizePair = MatrixScreenSaverOptions.characterSizePairs[sizeIndex]
         let neoMessageSpeedFactor = try parseDouble(from: neoMessageSpeedFactorField, error: .neoMessageSpeedFactor)
         let cmdOutputHoldSeconds = try parseDouble(from: cmdOutputHoldSecondsField, error: .cmdOutputHoldSeconds)
         guard cmdOutputHoldSeconds.isFinite, cmdOutputHoldSeconds >= 0 else {
             throw ValidationError.cmdOutputHoldSeconds
         }
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

        return MatrixScreenSaverOptions(
            neoMessageSceneEnabled: neoMessageSceneCheckbox.state == .on,
            neoMessageSpeedFactor: neoMessageSpeedFactor,
            name: nameField.stringValue,
            neoMessageLines: pendingLines,
            cmdSceneEnabled: cmdSceneCheckbox.state == .on,
            cmdOutputHoldSeconds: cmdOutputHoldSeconds,
             commands: pendingCommands,
             commandsRunInSequence: commandsSequenceRadio.state == .on || commandsShuffleRadio.state == .on,
             commandsShuffleSequence: commandsShuffleRadio.state == .on,
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
            rainFonts: selectedRainFonts,
            rainGlyphSet: selectedRainGlyphSet,
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
