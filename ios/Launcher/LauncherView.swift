//  LauncherView.swift -- the launcher UI.
//
//  Three tabs: getting the game data in, graphics, and controls. Play stays
//  disabled until pak0.pk3 is present, which is the one thing that otherwise
//  sends the engine straight into a fatal error on startup.
//
//  Russian throughout, since that is the language the person playing this reads.
//
//  Two things run through the whole file. The colours are the system's, so the
//  launcher follows the iPad's own light or dark setting instead of being
//  painted black regardless; and every screen can be driven from the controller
//  as well as by finger, through the cursor in LauncherPad.swift. Neither takes
//  anything away from the other: the focus ring appears only when a pad is
//  connected, and every control it lands on is still there to be tapped.

import SwiftUI
import UIKit

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @StateObject private var pad = PadInput()
    @State private var scope = PadScope()
    @State private var tab: Int
    @State private var language = Loc.current

    /// The footer is a screen of its own as far as the pad is concerned. It
    /// claims the top scope while the cursor is on it, which is the same
    /// mechanism a sheet uses, and the tab underneath then ignores the pad
    /// instead of moving its own cursor to the same strokes.
    @State private var footerScope = PadScope()

    /// How far the footer's fill runs on past the row of content it holds --
    /// the home indicator's inset, read once the window exists. See `footer`.
    @State private var bottomInset: CGFloat = 0

    /// The MP application carries two extra tabs -- finding a game and running
    /// one -- and swaps Campaign for the multiplayer settings, so the count is
    /// not a constant.
    private static var tabCount: Int { 7 }

    /// The tab the launcher opens on is decided here rather than being a
    /// constant on `tab`, because the model is built before the view is and by
    /// this point it has already scanned the folder: the answer is known, and a
    /// starting value chosen without it would be a guess corrected a frame later.
    ///
    /// The campaign set decides, not `canPlay`. `canPlay` asks only whether
    /// pak0.pk3 is there, which is enough for the engine to start and not enough
    /// for there to be a campaign to start -- with pak0 alone the Campaign tab
    /// is twenty-six missions whose maps do not exist. `isPlayable` on the
    /// campaign set asks the question the tab is actually about, so a player
    /// whose copy is half finished still lands on Data, where the checklist
    /// tells them which files are still missing.
    init(model: LauncherModel) {
        self.model = model

        // The Picker's tags, in the order the tabs are written below. In the MP
        // application the set that matters is the multiplayer one, and tab 1 is
        // the server browser rather than the campaign.
        // Debug aid: a script driving the simulator has no way to tap a tab, so
        // it can name one instead. Unset in normal use.
        if let forced = UserDefaults.standard.object(forKey: "IORTCWStartTab") as? Int {
            _tab = State(initialValue: forced)
        } else {
            // Whichever half of the game is actually installed decides where to
            // open. Campaign first, because that is the one most copies have.
            let campaignReady = model.dataSet(.campaign)?.isPlayable ?? false
            let mpReady = model.dataSet(.multiplayer)?.isPlayable ?? false
            _tab = State(initialValue: campaignReady ? 1 : (mpReady ? 2 : 0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Capped and left-aligned rather than stretched across the iPad.
            // Four segments over 1366 points is 340 points of empty plate per
            // tab, which reads as a stretched widget rather than as navigation;
            // at this width the labels sit close enough together to be taken in
            // at one look. It starts on the same left line as the emblem above
            // it and the content below, so the screen hangs off one edge.
            Picker("", selection: $tab) {
                Text(L("Данные")).tag(0)
                Text(L("Кампания")).tag(1)
                Text(L("Серверы")).tag(2)
                Text(L("Мультиплеер")).tag(3)
                Text(L("Свой сервер")).tag(4)
                Text(L("Графика")).tag(5)
                Text(L("Управление")).tag(6)
            }
            .pickerStyle(.segmented)
            // Seven tabs now, not four: at 620 the two longest were being
            // truncated to "Мультипле..." and "Свой серв...", which is worse
            // than the widget looking a little stretched.
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.m)

            Divider()

            Group {
                switch tab {
                case 0: DataView(model: model, pad: pad, scope: scope, onFooter: enterFooter)
                case 1: CampaignView(model: model, pad: pad, scope: scope, onFooter: enterFooter)
                case 2: ServersView(model: model, mp: model.mp)
                case 3: MultiplayerSettingsView(mp: model.mp)
                case 4: HostView(model: model, mp: model.mp)
                case 5: GraphicsView(model: model, pad: pad, scope: scope, onFooter: enterFooter)
                default: ControlsView(model: model, pad: pad, scope: scope, onFooter: enterFooter)
                }
            }

            footer
        }
        .background(Theme.background.ignoresSafeArea())
        // One accent for every control the system draws for us. Left alone, a
        // slider is iOS blue and a switch is iOS green, which is two more
        // colours on a screen that already carries the brand's red and the
        // launcher's orange -- and neither of the two means anything here.
        .tint(Theme.accent)
        .padScope(pad, scope)
        // The poll runs only while the launcher is up. It is put over the game
        // and taken down again, and a timer left behind would go on reading the
        // pad that is by then being used to play with.
        .onAppear {
            pad.start()
            bottomInset = LauncherView.safeAreaBottom()
        }
        .onDisappear { pad.stop() }
        .onReceive(pad.strokes) { key in
            if pad.isActive(footerScope) {
                footerStroke(key)
                return
            }
            guard pad.isActive(scope) else { return }
            switch key {
            case .tabPrev: tab = (tab + LauncherView.tabCount - 1) % LauncherView.tabCount
            case .tabNext: tab = (tab + 1) % LauncherView.tabCount
            // Options starts the game from wherever the cursor happens to be,
            // the way a console menu keeps one button that always means "go".
            case .start: if model.canPlay { model.play() }
            default: break
            }
        }
    }

    /// Whether the pad cursor is sitting on the Campaign button.
    ///
    /// Drawn only while a pad is connected, like every other cursor in the
    /// launcher: with a finger there is nothing to move and nothing to show.
    private var footerFocused: Bool { pad.connected && pad.isActive(footerScope) }

    /// Reached by walking the cursor off the bottom of the tab's own list,
    /// which is how a console menu runs out of a column of rows and into the
    /// buttons underneath it.
    private func enterFooter() {
        pad.claim(footerScope)
    }

    /// Released on the next turn of the runloop rather than here. The stroke
    /// that leaves the footer is still being handed round the subscribers, and
    /// dropping the scope inside that delivery would let the same press move
    /// the list's cursor as well.
    private func leaveFooter() {
        Task { @MainActor in pad.release(footerScope) }
    }

    private func footerStroke(_ key: PadKey) {
        switch key {
        case .up, .back:
            leaveFooter()
        case .confirm, .start:
            if model.canPlay { model.play() }
        case .tabPrev:
            leaveFooter()
            tab = (tab + LauncherView.tabCount - 1) % LauncherView.tabCount
        case .tabNext:
            leaveFooter()
            tab = (tab + 1) % LauncherView.tabCount
        // Down has nowhere further to go, and there is one button to be on, so
        // sideways has nothing to move between.
        case .down, .left, .right:
            break
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            // The same eagle as the app icon, so the launcher and the home
            // screen are recognisably one thing. The artwork is red on
            // transparent, which is legible on either theme's ground, so it
            // takes no tint and needs nothing behind it.
            Image("WolfLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)

            WolfTitle()

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let name = model.controllerName {
                    // The connection, and nothing else. The layout of the pad
                    // in the launcher was written out under here and has been
                    // taken away again: it is four button names' worth of text
                    // in the corner of a screen that is driven by trying it,
                    // and it was read once and then in the way for good.
                    Label(name, systemImage: "gamecontroller.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Label(L("Нет контроллера"), systemImage: "gamecontroller")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
    }

    /// The bar the launcher ends on.
    ///
    /// Language at the left, where reading starts and where a setting chosen
    /// once belongs; the state of the game data in the middle, on the way to
    /// the button; the button in the right corner, which is where a thumb
    /// already is on a tablet held in two hands.
    ///
    /// The three take a third of the width each rather than being pushed apart
    /// by spacers. The left group is far narrower than the right one, so with
    /// spacers the middle would settle wherever the two ends left room -- which
    /// is not the middle of the screen, and the middle of the screen is where
    /// the eye looks for it.
    ///
    /// What was wrong before was not where the three stood but that they were
    /// three unrelated shapes at three different heights: a segmented control,
    /// a bare word of green text floating with nothing around it, and a block
    /// of colour with a caption hanging underneath that made the bar taller
    /// than the block itself. Three things changed. Everything now sits on one
    /// centre line. The status is an object rather than a loose word -- a dot,
    /// a label, and a second line saying what is actually installed, which
    /// gives the middle third something to hold. And the pad hint stands beside
    /// the button instead of under it, which is what let the bar lose thirty
    /// points of height; that height is now file list on the data tab, which is
    /// what the player is reading while they copy the game in.
    ///
    /// The bar has a fill of its own, the same one the cards use. Without it
    /// the button was a block of colour lying on the page with nothing to
    /// belong to; with it the launcher reads as content between two pieces of
    /// chrome.
    private var footer: some View {
        HStack(alignment: .center, spacing: Space.xl) {
            languageChoice
                .frame(maxWidth: .infinity, alignment: .leading)

            readiness
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: Space.xl) {
                if model.controllerName != nil {
                    Text(L("Options — начать игру"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                multiplayerButton
                campaignButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.xl)
        // Not the same number top and bottom, so that what is seen is.
        //
        // The launcher lays out inside the safe area, but the bar's fill runs on
        // under the home indicator to the edge of the glass -- without that it
        // would end on a strip of background and stop being the edge of the
        // screen. So the panel the eye measures is taller at the bottom than the
        // row the content sits in, by exactly the inset, and content centred in
        // the row sits above the middle of the panel by half of it. Twelve above
        // and thirty-seven below is what that came to, and it is what was being
        // seen as the elements standing high in the bar.
        //
        // Here the lower gap is counted as it is drawn -- padding plus the strip
        // the fill spends under the indicator -- and the upper one is made equal
        // to it. The bar keeps its height to within a point: the twelve that
        // came off the bottom went to the top.
        .padding(.top, footerGap)
        .padding(.bottom, footerGap - bottomInset)
        .background(alignment: .top) {
            Theme.card
                .ignoresSafeArea(edges: .bottom)
                .overlay(Divider(), alignment: .top)
        }
    }

    /// The gap over the footer's content, and the gap under it once the strip
    /// the fill spends under the home indicator is counted in. The floor is
    /// there for a screen with no inset to give away -- an iPad with a button,
    /// the simulator's older models -- where the bar falls back to the padding
    /// it always had, top and bottom.
    private var footerGap: CGFloat { max(Space.m, bottomInset) }

    /// The safe area at the bottom, taken from the window because it can no
    /// longer be seen from inside the launcher: the stack is laid out within the
    /// safe area already, so a GeometryReader anywhere in it reports zero. Read
    /// on appear rather than at every redraw -- the window exists by then, and
    /// the number does not move while the launcher is up.
    private static func safeAreaBottom() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    /// Two words, rather than the segmented control that was here.
    ///
    /// A segmented control is a piece of widget as wide as the button at the
    /// other end of the bar, spent on a setting that is chosen once and then
    /// never again -- and on the light theme its white selected segment sits on
    /// a white bar and all but disappears. Two words, the current one in the
    /// text colour and the other in grey, say the same thing in a third of the
    /// space and read the same on either theme. Every string goes through L(),
    /// which reads Loc.current, so choosing here redraws the whole launcher.
    private var languageChoice: some View {
        HStack(spacing: Space.s) {
            ForEach(Array(Loc.Language.allCases.enumerated()), id: \.element) { index, choice in
                if index > 0 {
                    Text(verbatim: "·")
                        .font(TypeScale.status)
                        .foregroundStyle(Theme.hint)
                }
                Button {
                    Loc.select(choice)
                    language = choice
                } label: {
                    Text(choice.title)
                        .font(TypeScale.status.weight(language == choice ? .semibold : .regular))
                        .foregroundStyle(language == choice ? Color.primary : Color.secondary)
                        // The words are small and a finger is not. The padding
                        // is the touch target and nothing else draws on it.
                        .padding(.vertical, Space.s)
                        .padding(.horizontal, Space.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Whether the game can be started, said as a thing and not as a word.
    ///
    /// A dot and a label carry the state; the line under them says what that
    /// state is made of -- the size of the set that is going to load, or where
    /// to go when there is nothing to load. Two lines rather than one because a
    /// single short word in the middle of a wide bar has nothing to be measured
    /// against and looks dropped there; a block with a top and a bottom line
    /// stands at the height of the button opposite it and reads as its
    /// counterweight.
    private var readiness: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Circle()
                    .fill(model.canPlay ? Theme.ok : Theme.accent)
                    .frame(width: 8, height: 8)
                Text(model.canPlay ? L("Готово") : L("Нет игровых файлов"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.canPlay ? Theme.ok : Theme.accent)
            }
            Text(readinessDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Ready: the size of what is about to load. Not ready: where to go about
    /// it -- unless the player is already there, in which case telling them to
    /// open the page they are looking at is worse than saying nothing, so it
    /// counts what is missing instead.
    private var readinessDetail: String {
        if model.canPlay, let set = model.dataSet(model.primarySet), set.maps > 0 {
            return String(format: L("%ld карт · %.0f МБ"), set.maps, set.megabytes)
        }
        guard tab == 0, let set = model.dataSet(model.primarySet) else {
            return L("Откройте вкладку «Данные»")
        }
        return String(format: L("Не хватает файлов: %ld"),
                      set.files.filter { !$0.present }.count)
    }

    // A block rather than the pill a bordered button gives. At the width this
    // one needs, a pill reads as a bar of colour laid along the edge of the
    // screen; the one thing the screen is for should look like something to
    // press.
    //
    // 136x56 is the third pass, and it is where two requirements that pull
    // opposite ways meet. The block is meant to read as square-ish with a small
    // radius, and it is meant to be shorter, because the footer sits on top of
    // the data tab's file lists and every point of bar comes out of the list
    // the player is reading while they copy files in. Shortening alone would
    // have flattened it towards a bar -- 168x56 is three to one -- so the width
    // came down with the height and the proportion held: 2.4 to 1 against the
    // old 2.2, against the four to one of the capsule this replaced. Twenty
    // points of height went back to the list, and another sixteen came from
    // moving the pad hint out from under the button.
    //
    // The radius went from a fifth of the short side to a fourteenth. Ten
    // rounded the corner far enough that the block read as a rounded rectangle
    // -- which is what every card, row and panel on this screen already is --
    // and the one thing here that is not a panel should not be cut like one.
    // Four takes the raw point off the corner and no more: near enough to
    // square that the shape reads as a block, and not so square that a fill
    // this size looks like a crop out of something larger. The pad's focus ring
    // is drawn from the same number, six points out, so the cursor keeps the
    // button's shape rather than tracing a softer one around it.
    private static let tileWidth: CGFloat = 136
    private static let tileHeight: CGFloat = 56
    private static let tileRadius: CGFloat = 4

    /// Red, not the launcher's orange.
    ///
    /// It is the colour of the emblem and the wordmark at the top of the
    /// screen, so the eye runs from the title to the button and the two ends of
    /// the launcher belong to each other; and it is the one place the brand
    /// colour can be a fill without competing with the accent, which stays on
    /// the small controls where it marks what is selected.
    ///
    /// Of the two brand reds this is the darker, emblem one, because the label
    /// has to be read and not merely seen: white sits on it at 7:1, where the
    /// brighter wordmark red gives 4.6:1. White rather than the accent's black
    /// for the same reason -- black on this red is under 3:1 and would be the
    /// worst pairing on the screen. Neither theme changes any of that: the fill
    /// is fixed, and it separates from the ground either way, 6.3:1 on the
    /// light grey and 3:1 on the dark theme's black.
    private var campaignButton: some View {
        Button {
            model.play()
        } label: {
            // Cut from the same type as the header, because it is the other
            // end of the same screen. Eighteen points of bold body type was the
            // system's voice, and it made the one thing the launcher exists to
            // offer look like a control borrowed off a settings page and set
            // down under a wordmark in condensed capitals. Condensed, heavy,
            // capitals, letters opened up: that is the motif the header already
            // established and the player already likes, and the button now
            // speaks from inside it rather than from beside it.
            //
            // Twenty rather than eighteen because the condensed cut gives back
            // the width the larger size costs: КАМПАНИЯ comes out at about 103
            // points and the longer CAMPAIGN at about 91, both inside the 112
            // the block leaves between its paddings, so each language is set at
            // full size and minimumScaleFactor below is still only insurance.
            // Black was tried, being the wordmark's own weight, and left the
            // Russian two points off that limit -- a heavier weight buys nothing
            // here that the capitals have not already bought, and it would put
            // the next translation into the scale factor. Tracking 1.5 against
            // the wordmark's 1: capitals want more air the smaller they are set,
            // and this lands the label between the wordmark's tight lock-up and
            // the wide-spaced line above it, which is where a button belongs.
            Text(L("Кампания"))
                .font(.system(size: 20, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .tracking(1.5)
                .lineLimit(1)
                // Insurance for a language whose word for this is longer than
                // either of the two the launcher speaks.
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Space.m)
                .frame(width: LauncherView.tileWidth, height: LauncherView.tileHeight)
                .foregroundStyle(model.canPlayCampaign ? Theme.onAction : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: LauncherView.tileRadius, style: .continuous)
                        .fill(model.canPlayCampaign ? Theme.action : Theme.fill(0.10))
                )
        }
        .buttonStyle(TilePress())
        .disabled(!model.canPlayCampaign)
        .padFocusRing(footerFocused, radius: LauncherView.tileRadius)
    }

    /// The other half of the game, next to the campaign rather than instead of
    /// it: one binary carries both, and which one a launch is only gets decided
    /// here.
    ///
    /// Drawn in the same block as the campaign but in the neutral fill, because
    /// the two are not equals on this screen -- the campaign is what most
    /// copies of RTCW are, and the brand red belongs to it.
    private var multiplayerButton: some View {
        Button {
            model.mp.play()
        } label: {
            Text(L("Мультиплеер"))
                .font(.system(size: 20, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Space.m)
                .frame(width: LauncherView.tileWidth, height: LauncherView.tileHeight)
                .foregroundStyle(model.canPlayMultiplayer ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: LauncherView.tileRadius, style: .continuous)
                        .fill(Theme.fill(model.canPlayMultiplayer ? 0.16 : 0.10))
                )
        }
        .buttonStyle(TilePress())
        .disabled(!model.canPlayMultiplayer)
    }
}

/// Presses the block in when it is touched.
///
/// A tile drawn by hand gets none of the feedback a system button style would
/// have given it, and a button this size that does not move under the finger
/// reads as one that did not register the press.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The two title lines, the upper one spaced out to the width of the wordmark
/// below it.
///
/// The spacing is laid out rather than typed in. A tracking value fitted by eye
/// fits one string in one font at one size, and the moment either line changes
/// -- another language, another weight -- it is left short or overhanging. Here
/// the letters of the upper line are separate views with flexible gaps between
/// them, so the stack sizes itself to the wordmark and the gaps take up exactly
/// whatever slack there is. Nothing is measured and nothing is stored: it comes
/// out right for whatever text is put in it.
private struct WolfTitle: View {
    private static let upper = "RETURN TO CASTLE"
    private static let lower = "WOLFENSTEIN"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                let letters = Array(WolfTitle.upper)
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    // A plain space on its own is trailing whitespace as far as
                    // the type setter is concerned and measures nothing, which
                    // would close up the gaps between words.
                    Text(letter == " " ? "\u{00A0}" : String(letter))
                    if index < letters.count - 1 {
                        // minLength 0, so the ideal width of this row is the
                        // text alone and the stack is sized by the wordmark.
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 12, weight: .heavy))
            .fontWidth(.condensed)
            .foregroundStyle(Theme.emblem)
            // Split into letters it would otherwise be read out one at a time.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(WolfTitle.upper))

            Text(WolfTitle.lower)
                .font(.system(size: 32, weight: .black))
                .fontWidth(.condensed)
                .tracking(1)
                .foregroundStyle(Theme.wordmark)
        }
        // Without this the flexible row above would claim the whole header.
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Метрика

/// The one spacing scale the launcher measures with.
///
/// Every gap on the screen is one of these six values. The file used to mix
/// 4, 6, 8, 12, 16, 18, 24 and 26 without a rule, and a page whose distances
/// are all slightly different reads as assembled rather than laid out -- the
/// eye cannot tell a deliberate gap from a leftover one when no two are the
/// same. The steps roughly double, so two of them are never close enough to be
/// confused with each other.
enum Space {
    /// Inside a line: a dot and its label, a number and its unit.
    static let xs: CGFloat = 4
    /// Between the rows of one list.
    static let s: CGFloat = 8
    /// Between the parts of one group: a heading and what it heads.
    static let m: CGFloat = 12
    /// Card padding, and the gap between a control and its neighbour.
    static let l: CGFloat = 16
    /// The page margin, and the gap between one block and the next.
    static let xl: CGFloat = 24
    /// Between columns, and between one section of the page and another.
    static let xxl: CGFloat = 32
}

/// The corner of a card. One value, so panels, lists and blocks are cut the
/// same way; the action button is deliberately tighter, see `tileRadius`.
let cardRadius: CGFloat = 14

/// The corner of a control the system draws for us -- what a segmented picker
/// is cut to, and therefore what a focus ring around one has to follow.
let controlRadius: CGFloat = 8

/// The launcher's ladder of type.
///
/// Five steps, each doing one job, and a step apart from its neighbours in both
/// size and weight. The data page used to set a section heading at 17 semibold
/// and the sentence under it at 16 regular, which is a difference the eye has
/// to look for; here a heading is 20 semibold and everything under it is 15 or
/// smaller, so the shape of the page is legible before a word of it is read.
enum TypeScale {
    /// The name of a block of content, and the only step above body weight.
    static let section = Font.system(.title3, design: .default).weight(.semibold)
    /// A statement about a block: the state it is in.
    static let status = Font.subheadline
    /// The label of a control, and the title of anything that can be pressed.
    /// A step above the prose around it, because it is the part of a settings
    /// page the eye jumps between when it is looking for something.
    static let row = Font.body
    /// Prose: notes, explanations, the paragraph under a heading.
    static let body = Font.subheadline
    /// A file name: monospaced so a column of them lines up, and a step above
    /// the rest of the small print because on the data page the names are the
    /// content and not a note about it.
    static let mono = Font.system(.callout, design: .monospaced)
    /// A path, a version, a commit -- monospaced for the same reason, but set
    /// small: these are read once when something has gone wrong, and the rest
    /// of the time they should not be shouting over the lists.
    static let monoSmall = Font.system(.caption, design: .monospaced)
    /// The small print: counts, units, sums.
    static let caption = Font.caption
    /// The name of a field, set over its value in caps.
    static let label = Font.caption2.weight(.semibold)
}

// MARK: - Цвета

/// The launcher's colours, named once.
///
/// The two reds are the game's own and are fixed: the wordmark is deliberately
/// a shade brighter than the emblem, because on black the emblem's red goes
/// muddy at text sizes, and the pair reads as one family rather than a
/// mismatch. Both hold up on a white ground as well, so they do not change with
/// the theme -- a brand colour that moves is not a brand colour.
///
/// Everything else is the system's, so the launcher follows the iPad's light or
/// dark setting. That is the whole reason there is a table here: a hand-picked
/// `Color.white.opacity(0.05)` is invisible the moment the ground turns white.
enum Theme {
    /// What the app icon is drawn in.
    static let emblem = Color(red: 0.70, green: 0.07, blue: 0.11)
    /// The wordmark, a step brighter so it holds up as type.
    static let wordmark = Color(red: 0.88, green: 0.17, blue: 0.14)

    /// The ground the launcher sits on, matching what a grouped Form expects
    /// behind it: pale grey in the light theme, near-black in the dark one.
    static let background = Color(uiColor: .systemGroupedBackground)
    /// Cards that stand off that ground, the same fill the Form gives its own
    /// rows so hand-built panels and Form sections look like one thing.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    /// Anything drawn over the ground -- tracks, chips, rings. Tied to the text
    /// colour rather than to white, so it inverts with the theme.
    static func fill(_ opacity: Double) -> Color { Color.primary.opacity(opacity) }

    /// The launcher's one accent, and the colour of the pad cursor. Orange in
    /// both themes: it is what the game's own menus highlight with, and it
    /// stays clear of the red marks in the header instead of competing. Every
    /// control the system draws is tinted with it as well, which is what keeps
    /// iOS blue off a screen that is already carrying two colours of its own.
    static let accent = Color.orange

    /// The faintest step of text: a chevron at the end of a row, a mark that is
    /// there to be found and not to be read. Written out as a colour rather
    /// than as the hierarchical `.tertiary`, because inside a button that
    /// hierarchy resolves against the button's tint and quietly comes out
    /// orange -- which is how the graphics page shipped a paragraph of accent
    /// coloured body text without anyone writing one.
    static let hint = Color(uiColor: .tertiaryLabel)

    /// Present, found, connected. Named rather than written as `Color.green`
    /// at each of its half-dozen sites, because it is one meaning and it has
    /// to be possible to see every place that claims it -- three unrelated
    /// colours on one screen is already the limit, and a fourth creeping in
    /// under a system name is how a palette goes.
    static let ok = Color.green
    /// Text and glyphs sitting on top of the accent. Orange is light in either
    /// theme, so this is black in either theme.
    static let onAccent = Color.black

    /// The fill under the one action the launcher exists to offer. The emblem's
    /// red, so that the button belongs to the title above it rather than
    /// introducing a third colour; the darker of the two brand reds, because
    /// this is the one white text can live on. See `campaignButton`.
    static let action = emblem
    /// Text on that fill. White in both themes.
    static let onAction = Color.white
}

// MARK: - Панели

/// A titled block of settings: a heading, and a card of controls under it.
///
/// This is what a grouped `Form` draws for itself, drawn by hand instead. A
/// Form is one column and can be nothing else, and one column across thirteen
/// hundred points puts a switch's label against one edge of the screen and the
/// switch against the other with the whole of the middle empty -- which is what
/// made the two settings tabs look like a different, emptier application than
/// the two tabs beside them. Laid out by hand they take the same two columns
/// the data page does, and a row becomes a measure a label and its control can
/// be read across together.
///
/// The heading is the launcher's own section type rather than the Form's small
/// grey caps, so a block of settings weighs the same as a block of anything
/// else here.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(TypeScale.section)

            VStack(alignment: .leading, spacing: Space.l) {
                content
            }
            // Set once for the whole panel rather than on every label in it:
            // a row's type is a property of the panel, and thirty repetitions
            // of the same modifier is thirty chances for one of them to drift.
            .font(TypeScale.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
    }
}

/// A control and the sentence explaining it, as one thing.
///
/// The note is tied to its control at half the distance that separates one
/// control from the next. That ratio is the whole of what makes a stack of
/// settings legible: the eye groups by proximity before it reads a word, and a
/// note set as far from the control above it as from the one below belongs to
/// neither of them.
struct Field<Content: View>: View {
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            content
            if let note {
                Text(note)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A slider row: what it sets, the value it is at, and the track under both.
///
/// Two lines rather than one. On one line the name sat against one edge of the
/// screen and its number against the other, an iPad's width apart, with the
/// track filling the gap -- so checking a setting against its value meant
/// crossing eleven hundred points to do it. Over two lines the name and the
/// number share a line the width of a panel, every number in a column falls on
/// the same right edge, and the track gets the full width of the panel under
/// them, which is also the longest and therefore the most precise it can be.
/// The readout is monospaced so that the line does not shift as the digits
/// change under the thumb.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.l) {
                Text(title)
                    .font(TypeScale.row)
                Spacer(minLength: Space.l)
                Text(readout)
                    .font(TypeScale.row.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// A choice between a handful of things, with its name written above it.
///
/// Above, and not beside: a segmented control put in a Form row swallows its
/// own label, and the graphics page has been shipping a row reading "60 / 90 /
/// 120" with nothing anywhere to say what it is sixty of. The name costs one
/// line and answers the question.
///
/// The pad cursor is drawn as a ring around the pair rather than as the filled
/// plate the other rows get. A segmented control's unselected segments are
/// translucent, and a wash of orange laid behind them comes through as mud.
struct ChoiceRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    let focused: Bool
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(TypeScale.row)
            Picker("", selection: $selection) {
                options
            }
            .pickerStyle(.segmented)
            .padFocusRing(focused, radius: controlRadius)
        }
    }
}

/// A sentence that belongs to a whole panel rather than to any one control in
/// it -- the ones that used to sit at the end of a Form section.
struct Note: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(TypeScale.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row that opens something else: a sheet, or a list one level down.
private struct PressRow: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Space.s) {
                Text(title)
                    .font(TypeScale.row)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                Spacer(minLength: Space.l)
                if role != .destructive {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.hint)
                }
            }
        }
        // Plain, so that the row keeps the colours it was written with. Any
        // other button style hands its tint to whatever inside the label did
        // not name a colour of its own.
        .buttonStyle(.plain)
    }
}

// MARK: - Данные

/// What is on the device, in two parts: the campaign's files and multiplayer's.
///
/// They are separate because they are two different questions. The campaign set
/// decides whether the game starts at all -- without pak0.pk3 the engine dies
/// inside FS_Startup -- while the multiplayer set is a report and nothing more:
/// this binary has no multiplayer in it, and the section says so rather than
/// leaving a checklist that looks like a way in.
private struct DataView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    let onFooter: () -> Void

    /// Nothing on this page can be pressed -- it is two checklists and a couple
    /// of paragraphs -- so the pad only scrolls it. Drawing a focus ring on a
    /// row that would do nothing when confirmed would be a promise the page
    /// cannot keep. Two stops, the top and the bottom, because the page is laid
    /// out to fit and a stop in the middle of a page that does not scroll is a
    /// press that appears to do nothing. Past the last one the cursor leaves
    /// for the footer.
    @State private var mark = 0
    private static let marks = 1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    // Full width, above both columns, and only while the
                    // campaign is short of something: it is the same folder and
                    // the same Finder for either set, so saying it twice would
                    // be twice the wall of text, and a wall that stays up after
                    // the data has arrived is in the way of the answer the
                    // player came back for. It runs the width of the page
                    // because while it is there it is the only thing on the
                    // screen that matters.
                    if !campaignComplete {
                        instructions
                    }

                    // Two columns rather than one column and a scrollbar.
                    //
                    // The two sets are twenty rows of short monospaced names on
                    // a screen thirteen hundred points wide: stacked, they run
                    // off the bottom and the player copying files in has to
                    // scroll to see whether the thing they just copied arrived,
                    // while eight hundred points of every row sits empty. Side
                    // by side the whole of both fits above the footer at once,
                    // nothing is dropped from either list, and each list gets a
                    // measure a name can be read across rather than a line the
                    // eye has to travel.
                    //
                    // The campaign is on the left, where reading starts, since
                    // it is the set that decides whether the game runs at all;
                    // what is installed and which build is running goes under
                    // it, filling the room the shorter list leaves and giving
                    // the left column a bottom edge of its own.
                    HStack(alignment: .top, spacing: Space.xxl) {
                        // The spacer is what gives the two columns one bottom
                        // edge. The campaign set is a third of the length of
                        // the multiplayer one, so left to itself the left
                        // column stopped halfway up the page and the block of
                        // content came out as a staircase; pushed down, the
                        // installation panel closes the rectangle and the
                        // whitespace collects in one band above the footer
                        // instead of in a notch inside the page.
                        VStack(alignment: .leading, spacing: Space.xl) {
                            section(.campaign)
                            installation
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                        section(.multiplayer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // The bottom of the page as somewhere to scroll to. Zero
                    // height, so it costs the layout nothing.
                    Color.clear.frame(height: 0).id(1)
                }
                .padding(Space.xl)
                .id(0)
            }
            .onReceive(pad.strokes) { key in
                guard pad.isActive(scope) else { return }
                switch key {
                case .up:
                    mark = max(mark - 1, 0)
                case .down:
                    guard mark < DataView.marks else { onFooter(); return }
                    mark += 1
                default:
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(mark, anchor: mark == 0 ? .top : .bottom)
                }
            }
        }
    }

    /// Whether the campaign has everything it lists -- which is what the
    /// copying instructions above are about.
    private var campaignComplete: Bool {
        model.dataSet(.campaign)?.isComplete ?? false
    }

    private var instructions: some View {
        HStack(alignment: .top, spacing: Space.l) {
            // The one glyph on the page. It is here because this block is a
            // job to be done rather than a report, and it wants to be picked
            // out of the page before it is read.
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s) {
                Text(L("Скопируйте данные Return to Castle Wolfenstein"))
                    .font(TypeScale.section)
                Text(L("note.data"))
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    /// Where the data lives and which build is reading it.
    ///
    /// Two label-and-value pairs in the same card the lists use, so the page is
    /// made of one kind of object throughout. The labels are set small and in
    /// caps: they are there to be found when something has gone wrong and read
    /// out over a telephone, and they must not compete with the two set names,
    /// which are what the page is about.
    private var installation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L("Установка"))
                .font(TypeScale.section)

            VStack(alignment: .leading, spacing: Space.l) {
                metaField(L("Папка"), model.dataPath + "/main")
                metaField(L("Сборка"), buildLine, second: model.engineVersion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.l)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
        // This panel is the one that takes up the slack.
        //
        // The campaign set is five files and the multiplayer set sixteen, so
        // the left column is a third of the height of the right and something
        // has to make up the difference or the page ends in a staircase. It is
        // this card rather than the list above it: a card of two fields with
        // room under them reads as a panel, while a list of five files with a
        // hundred and fifty points of nothing between the last of them and
        // their own summary reads as a list that lost its footing. The slack
        // goes where the page cares least about it, and both columns still
        // finish on one line.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func metaField(_ label: String, _ value: String, second: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(TypeScale.label)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(TypeScale.monoSmall)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let second {
                Text(second)
                    .font(TypeScale.monoSmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buildLine: String {
        var line = L("iORTCW для iPadOS") + " " + model.appVersion + " · #" + model.buildNumber
        // Nothing at all rather than a placeholder where the hash goes: an
        // em dash in a monospaced line looks like part of the version.
        if let commit = model.buildCommit {
            line += " · " + commit
        }
        return line
    }

    /// One set: what it wants, what is there, and what that adds up to.
    ///
    /// The name of the set and the state it is in share a line, on one baseline
    /// and pushed to the two edges of the card below them. They used to be two
    /// stacked lines, which put a heading and a sentence of nearly the same
    /// weight one above the other and left the eye to work out which was which;
    /// on one line the question is on the left and the answer is on the right,
    /// and it is read in a single movement.
    ///
    /// The campaign card stretches to the height of the multiplayer one beside
    /// it, and its summary is pushed to its own bottom edge. The two sets are
    /// five files and sixteen, so left at their natural heights the block of
    /// content came out as a staircase with a third of the left half of the
    /// page empty under it. A panel with its list at the top and its sum along
    /// the bottom is a shape that is meant to be that tall; a card that simply
    /// stops halfway is one that ran out.
    @ViewBuilder
    private func section(_ kind: DataSetKind, stretches: Bool = false) -> some View {
        let set = model.dataSet(kind)

        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text(L(kind == .campaign ? "Игровые файлы кампании"
                                         : "Игровые файлы мультиплеера"))
                    .font(TypeScale.section)
                Spacer(minLength: 0)
                status(of: set, claimsPlayable: kind == .campaign)
            }

            if kind == .multiplayer {
                Text(L(model.isMultiplayer ? "note.mpdata.mp" : "note.mpdata"))
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let set, !set.files.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    fileList(set)
                        .padding(Space.l)

                    if stretches {
                        Spacer(minLength: Space.l)
                    }

                    // Counted from the pk3 directories. Files of the right
                    // names prove nothing; 35 maps do. It sits inside the card
                    // under a rule rather than loose beneath it, because it is
                    // the sum of the rows above and belongs to them.
                    if kind == .campaign, set.maps > 0 {
                        Divider()
                        Text(String(format: L("%ld карт · %ld файлов · %.0f МБ распакованных данных"),
                                    set.maps, set.entries, set.megabytes))
                            .font(TypeScale.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Space.l)
                            .padding(.vertical, Space.m)
                    }

                    // Whether what the player has is the set they should have:
                    // complete at the last official patch level, with nothing
                    // missing and nothing wearing an id pak's name.
                    if kind == .multiplayer {
                        Divider()
                        Label(L("Полный официальный набор"),
                              systemImage: set.isRecommended ? "checkmark.circle.fill" : "circle.dotted")
                            .font(TypeScale.caption)
                            .foregroundStyle(set.isRecommended ? Theme.ok : Color.secondary)
                            .padding(.horizontal, Space.l)
                            .padding(.vertical, Space.m)
                    }
                }
                .frame(maxHeight: stretches ? .infinity : nil)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            }
        }
        .frame(maxHeight: stretches ? .infinity : nil, alignment: .top)
    }

    /// The files themselves, as a table rather than as a row of full-width
    /// lines.
    ///
    /// The note saying a file is required used to be pushed to the far right of
    /// the screen by a spacer, thirteen hundred points from the name it was
    /// about, which is far enough that the two have to be read as separate
    /// columns and matched up by eye. A Grid measures the name column once and
    /// sets every note against the same edge, so the mark stands next to what
    /// it marks and the table has two straight left lines instead of one left
    /// and one right.
    private func fileList(_ set: DataSetState) -> some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: Space.m,
             verticalSpacing: Space.m) {
            ForEach(set.files) { file in
                GridRow {
                    Image(systemName: file.present ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.footnote)
                        .foregroundStyle(file.present ? Theme.ok : Color.secondary)
                    Text(file.name)
                        .font(TypeScale.mono)
                        .foregroundStyle(file.present ? Color.primary : Color.secondary)
                    // Named only where it decides something: a file the set
                    // cannot do without, which is not on the device. Saying
                    // "required" next to one that is already there tells the
                    // player nothing.
                    if file.required && !file.present {
                        Text(L("обязателен"))
                            .font(TypeScale.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one line that says where a set stands.
    ///
    /// Playability is claimed for the campaign only. Nothing in this build can
    /// start a multiplayer game, so a line telling the player the multiplayer
    /// set is ready to play would be a promise the binary cannot keep -- there
    /// it says what is there and stops.
    @ViewBuilder
    private func status(of set: DataSetState?, claimsPlayable: Bool) -> some View {
        if let set, set.isComplete {
            Label(L("Все игровые файлы найдены."), systemImage: "checkmark.seal.fill")
                .font(TypeScale.status)
                .foregroundStyle(Theme.ok)
        } else if let set, set.isPlayable, claimsPlayable {
            Label(L("Набор неполный, но играть можно."), systemImage: "exclamationmark.triangle.fill")
                .font(TypeScale.status)
                .foregroundStyle(Theme.accent)
        } else {
            Label(L("Набор неполный."), systemImage: "circle.dotted")
                .font(TypeScale.status)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Кампания

private struct CampaignView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    let onFooter: () -> Void
    @State private var cursor = 0

    /// Three, and these three values: the game's own play.menu sets
    /// g_gameskill to 1, 2 or 3 and offers nothing else.
    private static let skills: [(value: Int, title: String)] = [
        (1, "Не делай мне больно"),
        (2, "Не так уж и плохо"),
        (3, "Смерть во плоти"),
    ]

    /// Four across.
    ///
    /// Twenty-six missions in one column is a list two and a half screens long
    /// with an eight-hundred-point gutter of nothing beside every name, and the
    /// player has to scroll to find out what the campaign even contains. Across
    /// four columns the whole of it is on the screen at once, which is what a
    /// chapter select is for: the campaign is a thing to be seen, not a list to
    /// be paged through. Four rather than three because a mission name is short
    /// -- the longest is under half of a three-column tile -- and three would
    /// leave each tile mostly empty.
    private static let columns = 4

    /// The order the pad walks. The difficulty picker is one control, the way
    /// the graphics presets are, so it takes a single place at the head of the
    /// list and left and right choose within it.
    private enum Row: Hashable {
        case skill
        case mission(String)
    }

    private var missions: [CampaignMission] { CampaignMission.all }

    private func focused(_ row: Row) -> Bool {
        guard pad.connected, pad.isActive(scope) else { return false }
        switch row {
        case .skill:            return cursor == 0
        case .mission(let id):  return cursor > 0 && missions[cursor - 1].id == id
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text(L("Сложность"))
                            .font(TypeScale.section)

                        // Written as one segmented control rather than as three
                        // rows of a list: three mutually exclusive choices with
                        // three short labels is what a segmented control is,
                        // and as a list it took three full-width rows out of
                        // the page for a setting that is chosen once.
                        // Exactly two of the four mission columns wide, and
                        // not a round number picked by eye: two equal halves
                        // either side of one column gap come out at the same
                        // edge the second tile of every row below ends on, at
                        // any screen width. A control that stops two points
                        // short of the column under it looks like a mistake in
                        // a way that one stopping halfway across does not.
                        HStack(spacing: Space.l) {
                            Picker("", selection: $model.skill) {
                                ForEach(CampaignView.skills, id: \.value) { skill in
                                    Text(L(skill.title)).tag(skill.value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)
                            // A ring rather than the filled plate: the
                            // segmented control's unselected segments are
                            // translucent, and a wash of orange laid behind
                            // them comes through as mud.
                            .padFocusRing(focused(.skill), radius: controlRadius)

                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 0)
                        }
                        .id(Row.skill)
                    }

                    VStack(alignment: .leading, spacing: Space.m) {
                        Text(L("Миссии"))
                            .font(TypeScale.section)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.l),
                                                 count: CampaignView.columns),
                                  spacing: Space.l) {
                            ForEach(missions) { mission in
                                missionTile(mission)
                            }
                        }
                    }

                    Text(L("note.campaign"))
                        .font(TypeScale.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // Prose does not want the width of an iPad. Held to a
                        // measure a line can be read across without the eye
                        // losing which line it is on.
                        .frame(maxWidth: 900, alignment: .leading)
                }
                .padding(Space.xl)
            }
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
    }

    /// One mission.
    ///
    /// The whole tile is the button, so there is nothing for a marker at the
    /// far end to explain, and the chevron is drawn in the third grey rather
    /// than in the accent: twenty-six orange arrows is not information, it is a
    /// colour appearing twenty-six times. The accent on this page is spent on
    /// the one thing it is for -- where the pad cursor is.
    private func missionTile(_ mission: CampaignMission) -> some View {
        Button {
            model.startMission(mission)
        } label: {
            HStack(spacing: Space.s) {
                Text(L(mission.title))
                    .font(TypeScale.row)
                    .foregroundStyle(model.canPlay ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.hint)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
        .buttonStyle(TilePress())
        .disabled(!model.canPlay)
        .id(Row.mission(mission.id))
        .padFocusRing(focused(.mission(mission.id)), radius: cardRadius)
    }

    /// Walking a grid rather than a column.
    ///
    /// Up and down move by a whole row, left and right by one tile, which is
    /// what the eye expects of something laid out in rows and columns -- a
    /// cursor that went 1, 2, 3 along a grid under the down button would be
    /// travelling sideways while the thumb pushed downwards. The difficulty
    /// control sits above the first row, so up out of it lands there and down
    /// from it comes back into the column it left.
    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let count = missions.count
        let cols = CampaignView.columns

        switch key {
        case .up:
            guard cursor > 0 else { return }
            let index = cursor - 1
            cursor = index < cols ? 0 : cursor - cols

        case .down:
            guard cursor > 0 else {
                cursor = 1
                break
            }
            let index = cursor - 1
            // Off the bottom row the cursor leaves for the footer, rather than
            // sitting against the end of the grid with nowhere to go. A shorter
            // last row catches the cursor at its end instead.
            guard index / cols < (count - 1) / cols else { onFooter(); return }
            cursor = min(index + cols, count - 1) + 1

        case .left:
            guard cursor > 0 else {
                padCycle(&model.skill, through: CampaignView.skills.map(\.value), forward: false)
                return
            }
            cursor = max(cursor - 1, 1)

        case .right:
            guard cursor > 0 else {
                padCycle(&model.skill, through: CampaignView.skills.map(\.value), forward: true)
                return
            }
            cursor = min(cursor + 1, count)

        case .confirm:
            guard cursor > 0, model.canPlay else { return }
            model.startMission(missions[cursor - 1])
            return

        default:
            return
        }

        let row: Row = cursor == 0 ? .skill : .mission(missions[cursor - 1].id)
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(row, anchor: .center)
        }
    }
}

// MARK: - Графика

private struct GraphicsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    let onFooter: () -> Void
    @State private var cursor = 0

    /// Declared in the order the eye reads the page: down the left column,
    /// then down the right one. The pad walks this list, so the two orders
    /// have to be the same one.
    private enum Row: CaseIterable, Hashable {
        case preset, fps, hiDPI, fov, brightness
    }

    private var rows: [Row] { Row.allCases }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Space.xxl) {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        // Three named choices with a sentence each, rather
                        // than a segmented control with one sentence under it
                        // that changes as the control moves. A player choosing
                        // between them wants to compare them, and a description
                        // that is only ever shown for the option already
                        // selected cannot be compared with anything. It costs a
                        // hundred points of height on the emptiest page in the
                        // launcher, which had them going spare.
                        Panel(L("Качество")) {
                            VStack(alignment: .leading, spacing: Space.l) {
                                ForEach(GraphicsPreset.allCases) { preset in
                                    presetRow(preset)
                                }
                            }
                            .id(Row.preset)
                            .padFocusRing(focused(.preset), radius: controlRadius)
                        }

                        Panel(L("Экран")) {
                            Field {
                                ChoiceRow(title: L("Кадры/с"),
                                          selection: $model.maxFPS,
                                          focused: focused(.fps)) {
                                    Text("60").tag(60)
                                    Text("90").tag(90)
                                    Text("120").tag(120)
                                }
                                .id(Row.fps)
                            }

                            Field(note: L(model.hiDPI
                                          ? "Рендер в родных 2752×2064."
                                          : "Половинное разрешение: мягче картинка, дольше батарея.")) {
                                Toggle(L("Полное разрешение"), isOn: $model.hiDPI)
                                    .id(Row.hiDPI)
                                    .padFocus(focused(.hiDPI))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Space.xl) {
                        Panel(L("Изображение")) {
                            Field {
                                SliderRow(title: L("Поле зрения"),
                                          value: $model.fov,
                                          range: 70...110,
                                          step: 5,
                                          readout: "\(Int(model.fov))°")
                                    .id(Row.fov)
                                    .padFocus(focused(.fov))
                            }

                            Field(note: L("Аппаратной гаммы на iOS нет, поэтому яркость запекается в текстуры и применяется при следующем запуске.")) {
                                SliderRow(title: L("Яркость"),
                                          value: $model.brightness,
                                          range: 1.0...2.5,
                                          step: 0.1,
                                          readout: String(format: "%.1f", model.brightness))
                                    .id(Row.brightness)
                                    .padFocus(focused(.brightness))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.xl)
            }
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
    }

    private func presetRow(_ preset: GraphicsPreset) -> some View {
        Button {
            model.preset = preset
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Image(systemName: model.preset == preset ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.preset == preset ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(L(preset.title))
                        .font(TypeScale.row)
                        .foregroundStyle(Color.primary)
                    Text(L(preset.detail))
                        .font(TypeScale.caption)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        // See PressRow: without this the descriptions come out in the tint.
        .buttonStyle(.plain)
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        switch key {
        case .up, .down:
            let next = cursor + (key == .down ? 1 : -1)
            // Down past the last row hands the cursor to the footer.
            guard next < rows.count else { onFooter(); return }
            cursor = max(next, 0)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor], anchor: .center)
            }
        case .left, .right, .confirm:
            guard rows.indices.contains(cursor) else { return }
            act(rows[cursor], key)
        default:
            break
        }
    }

    private func act(_ row: Row, _ key: PadKey) {
        let forward = key != .left
        switch row {
        case .preset:
            padCycle(&model.preset, through: GraphicsPreset.allCases, forward: forward)
        case .fps:
            padCycle(&model.maxFPS, through: [60, 90, 120], forward: forward)
        case .hiDPI:
            switch key {
            case .confirm: model.hiDPI.toggle()
            case .left:    model.hiDPI = false
            default:       model.hiDPI = true
            }
        case .fov:
            guard key != .confirm else { return }
            padStep(&model.fov, by: 5, in: 70...110, up: forward)
        case .brightness:
            guard key != .confirm else { return }
            padStep(&model.brightness, by: 0.1, in: 1.0...2.5, up: forward)
        }
    }
}

// MARK: - Управление

private struct ControlsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    let onFooter: () -> Void
    @State private var showBinds = false
    @State private var showTest = false
    @State private var cursor = 0

    /// Declared in the order the page is read: down the left column, then down
    /// the right one. The pad walks this list, so the two orders have to be the
    /// same order or the cursor jumps about the screen. `rows` drops the ones
    /// that are only sometimes drawn.
    private enum Row: CaseIterable, Hashable {
        // The controller, down the left.
        case moveDigital, yaw, pitch, deadzone, invertLook
        case rumble, rumbleImpact, rumbleImpactScale, adaptive
        case gyroMode, gyroSplit, gyroSens, gyroYawSens, gyroPitchSens
        case gyroInvertYaw, gyroInvertPitch, gyroYawSource
        case test, binds, reset
        // Everything else, down the right.
        case touchControls
        case touchLookSplit, touchLookSens, touchLookYawSens, touchLookPitchSens
        case touchGyro, touchGyroSplit, touchGyroSens, touchGyroYawSens, touchGyroPitchSens
        case touchGyroInvertYaw, touchGyroInvertPitch
        case volume, music
        case autoSwitch, autoActivate, emptySwitch, viewBob, crosshair
        case perfHud, perfLog, padLog
    }

    /// What a row does when it is confirmed or pushed sideways. Written as one
    /// table so a row cannot be drawn and driven by two different rules.
    private enum Kind {
        case flag(ReferenceWritableKeyPath<LauncherModel, Bool>)
        case range(ReferenceWritableKeyPath<LauncherModel, Double>, ClosedRange<Double>, Double)
        case choice(ReferenceWritableKeyPath<LauncherModel, Int>, [Int])
        case press(() -> Void)
    }

    private var rows: [Row] {
        Row.allCases.filter { row in
            switch row {
            case .rumbleImpact:
                // With the motors at zero there is nothing for this to switch
                // on, and a control that visibly does nothing is worse than one
                // that is not there. Same reasoning as the gyro rows below.
                return model.rumble > 0
            case .rumbleImpactScale:
                // It scales the kick this switch turns on, so with the switch
                // off there is nothing for it to be a scale of.
                return model.rumble > 0 && model.rumbleImpact
            case .gyroSplit, .gyroInvertYaw, .gyroInvertPitch, .gyroYawSource:
                return model.gyroMode != 0
            // The common slider and the pair that replaces it are the same row
            // of the page in two states, so exactly one of them is ever drawn.
            case .gyroSens:
                return model.gyroMode != 0 && !model.gyroSplitAxes
            case .gyroYawSens, .gyroPitchSens:
                return model.gyroMode != 0 && model.gyroSplitAxes
            case .touchLookSens:
                return !model.touchLookSplitAxes
            case .touchLookYawSens, .touchLookPitchSens:
                return model.touchLookSplitAxes
            case .touchGyroSplit, .touchGyroInvertYaw, .touchGyroInvertPitch:
                return model.touchGyro != 0
            case .touchGyroSens:
                return model.touchGyro != 0 && !model.touchGyroSplitAxes
            case .touchGyroYawSens, .touchGyroPitchSens:
                return model.touchGyro != 0 && model.touchGyroSplitAxes
            default:
                return true
            }
        }
    }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Space.xxl) {
                    controller
                        .frame(maxWidth: .infinity, alignment: .leading)
                    everythingElse
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.xl)
            }
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
        .sheet(isPresented: $showBinds) { BindingsView(model: model, pad: pad) }
        .sheet(isPresented: $showTest) { ControllerTestView(pad: pad) }
    }

    /// The left column: everything that is about the thing in the player's
    /// hands -- how its sticks read, how it pushes back, and what its buttons
    /// are bound to. The split is by what the setting belongs to and not by how
    /// tall the panels came out, but it happens to balance: the two columns end
    /// within a panel's height of each other.
    private var controller: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Panel(L("Стики")) {
                Field(note: L(model.moveDigital
                              ? "Левый стик работает как WASD: северо-восток — это вперёд и вправо. Предсказуемо и без сноса."
                              : "Плавное аналоговое движение.")) {
                    Toggle(L("Движение по 8 направлениям"), isOn: $model.moveDigital)
                        .id(Row.moveDigital)
                        .padFocus(focused(.moveDigital))
                }

                Field {
                    SliderRow(title: L("Скорость поворота"),
                              value: $model.lookYawSpeed,
                              range: 60...400, step: 10,
                              readout: String(format: L("%ld°/с"), Int(model.lookYawSpeed)))
                        .id(Row.yaw)
                        .padFocus(focused(.yaw))
                }

                Field {
                    SliderRow(title: L("Вертикаль"),
                              value: $model.lookPitchSpeed,
                              range: 40...300, step: 10,
                              readout: String(format: L("%ld°/с"), Int(model.lookPitchSpeed)))
                        .id(Row.pitch)
                        .padFocus(focused(.pitch))
                }

                Field {
                    SliderRow(title: L("Мёртвая зона"),
                              value: $model.stickDeadzone,
                              range: 0.02...0.35, step: 0.01,
                              readout: String(format: "%.0f%%", model.stickDeadzone * 100))
                        .id(Row.deadzone)
                        .padFocus(focused(.deadzone))
                }

                Field {
                    Toggle(L("Инверсия вертикали"), isOn: $model.invertLook)
                        .id(Row.invertLook)
                        .padFocus(focused(.invertLook))
                }
            }

            Panel("DualSense") {
                Field(note: L("note.haptics")) {
                    SliderRow(title: L("Вибрация"),
                              value: $model.rumble,
                              range: 0...100, step: 5,
                              readout: "\(Int(model.rumble))%")
                        .id(Row.rumble)
                        .padFocus(focused(.rumble))
                }

                if model.rumble > 0 {
                    Field(note: L("note.impact")) {
                        Toggle(L("Отдача при попадании"), isOn: $model.rumbleImpact)
                            .id(Row.rumbleImpact)
                            .padFocus(focused(.rumbleImpact))
                    }

                    if model.rumbleImpact {
                        Field(note: L("note.impactscale")) {
                            SliderRow(title: L("Сила отдачи"),
                                      value: $model.rumbleImpactScale,
                                      range: 0...2, step: 0.05,
                                      readout: "\(Int((model.rumbleImpactScale * 100).rounded()))%")
                                .id(Row.rumbleImpactScale)
                                .padFocus(focused(.rumbleImpactScale))
                        }
                    }
                }

                Field {
                    Toggle(L("Адаптивные триггеры"), isOn: $model.adaptiveTriggers)
                        .id(Row.adaptive)
                        .padFocus(focused(.adaptive))
                }

                // The switch that turns the gyro on comes before the settings
                // that only exist while it is on. It used to come after them,
                // which asked the player to read four controls before reaching
                // the one that decides whether any of them are there.
                Field {
                    ChoiceRow(title: L("Гироскоп"),
                              selection: $model.gyroMode,
                              focused: focused(.gyroMode)) {
                        Text(L("Выкл")).tag(0)
                        Text(L("Всегда")).tag(1)
                        Text(L("В прицеле")).tag(2)
                    }
                    .id(Row.gyroMode)
                }

                if model.gyroMode != 0 {
                    // One switch, not two extra sliders beside the one that is
                    // already there. The per-axis keys mean "nothing set here"
                    // at zero, which is not a position a slider can offer:
                    // a player who set one and then reached for the common
                    // figure would find it doing nothing, with no way to see
                    // why. So the two states are drawn as two states, and the
                    // switch decides which of them is on the page.
                    Field {
                        Toggle(L("Раздельно по осям"), isOn: $model.gyroSplitAxes)
                            .id(Row.gyroSplit)
                            .padFocus(focused(.gyroSplit))
                    }

                    if model.gyroSplitAxes {
                        Field {
                            SliderRow(title: L("Чувствительность по горизонтали"),
                                      value: $model.gyroYawSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.gyroYawSens))
                                .id(Row.gyroYawSens)
                                .padFocus(focused(.gyroYawSens))
                        }

                        Field {
                            SliderRow(title: L("Чувствительность по вертикали"),
                                      value: $model.gyroPitchSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.gyroPitchSens))
                                .id(Row.gyroPitchSens)
                                .padFocus(focused(.gyroPitchSens))
                        }
                    } else {
                        Field {
                            SliderRow(title: L("Чувствительность гироскопа"),
                                      value: $model.gyroSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.gyroSens))
                                .id(Row.gyroSens)
                                .padFocus(focused(.gyroSens))
                        }
                    }

                    // Which way a gyro should turn the view is not something
                    // the code can work out -- only the person holding it knows
                    // it is going the wrong way -- so it is a switch, one per
                    // axis.
                    Field {
                        Toggle(L("Инверсия гироскопа по горизонтали"), isOn: $model.gyroInvertYaw)
                            .id(Row.gyroInvertYaw)
                            .padFocus(focused(.gyroInvertYaw))
                    }

                    Field(note: L("Только гироскоп контроллера — у планшета свои переключатели.")) {
                        Toggle(L("Инверсия гироскопа по вертикали"), isOn: $model.gyroInvertPitch)
                            .id(Row.gyroInvertPitch)
                            .padFocus(focused(.gyroInvertPitch))
                    }

                    // Which movement of the pad turns the view sideways. Not a
                    // thing anyone can be asked to work out from a cvar: it is
                    // how the controller is held, and the only way to find out
                    // which suits a player is to let them try the other one.
                    Field(note: L("note.gyroyaw")) {
                        ChoiceRow(title: L("Горизонталь гироскопа"),
                                  selection: $model.gyroYawSource,
                                  focused: focused(.gyroYawSource)) {
                            Text(L("Разворот")).tag(0)
                            Text(L("Крен")).tag(1)
                            Text(L("Оба")).tag(2)
                        }
                        .id(Row.gyroYawSource)
                    }
                }
            }

            Panel(L("Раскладка")) {
                Field {
                    PressRow(title: L("Проверка контроллера…")) { showTest = true }
                        .id(Row.test)
                        .padFocus(focused(.test))
                }
                Field {
                    PressRow(title: L("Настроить кнопки…")) { showBinds = true }
                        .id(Row.binds)
                        .padFocus(focused(.binds))
                }
                Field(note: L("note.layout")) {
                    PressRow(title: L("Сбросить к стандартной"), role: .destructive) {
                        model.applyDefaultBindings()
                    }
                    .id(Row.reset)
                    .padFocus(focused(.reset))
                }
            }
        }
    }

    /// The right column: the screen, the sound, the game, and the switches that
    /// are only there when something has gone wrong.
    private var everythingElse: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Panel(L("Экранные кнопки")) {
                Field(note: L("note.touch")) {
                    ChoiceRow(title: L("Показывать"),
                              selection: $model.touchControls,
                              focused: focused(.touchControls)) {
                        Text(L("Автоматически")).tag(0)
                        Text(L("Всегда")).tag(1)
                        Text(L("Никогда")).tag(2)
                    }
                    .id(Row.touchControls)
                }

                Note(L("note.menu"))
            }

            // Looking about with a finger and tilting the iPad are two
            // different ways of aiming that happen to share a screen, and until
            // now they shared a list as well -- with the pad's own gyro
            // settings a column away, and the iPad's crowded in under the
            // touch buttons. Each has its own heading now, and each carries
            // everything that belongs to it.
            Panel(L("Обзор пальцем")) {
                Note(L("Насколько поворачивается вид за движение пальца по правой половине экрана."))

                Field {
                    Toggle(L("Раздельно по осям"), isOn: $model.touchLookSplitAxes)
                        .id(Row.touchLookSplit)
                        .padFocus(focused(.touchLookSplit))
                }

                if model.touchLookSplitAxes {
                    Field {
                        SliderRow(title: L("Чувствительность по горизонтали"),
                                  value: $model.touchLookYawSens,
                                  range: 0.3...3.0, step: 0.1,
                                  readout: String(format: "%.1f", model.touchLookYawSens))
                            .id(Row.touchLookYawSens)
                            .padFocus(focused(.touchLookYawSens))
                    }

                    Field {
                        SliderRow(title: L("Чувствительность по вертикали"),
                                  value: $model.touchLookPitchSens,
                                  range: 0.3...3.0, step: 0.1,
                                  readout: String(format: "%.1f", model.touchLookPitchSens))
                            .id(Row.touchLookPitchSens)
                            .padFocus(focused(.touchLookPitchSens))
                    }
                } else {
                    Field {
                        SliderRow(title: L("Чувствительность обзора"),
                                  value: $model.touchLookSens,
                                  range: 0.3...3.0, step: 0.1,
                                  readout: String(format: "%.1f", model.touchLookSens))
                            .id(Row.touchLookSens)
                            .padFocus(focused(.touchLookSens))
                    }
                }
            }

            Panel(L("Гироскоп планшета")) {
                Field(note: L("note.gyro")) {
                    ChoiceRow(title: L("Режим"),
                              selection: $model.touchGyro,
                              focused: focused(.touchGyro)) {
                        Text(L("Выкл")).tag(0)
                        Text(L("Без контроллера")).tag(1)
                        Text(L("Всегда")).tag(2)
                    }
                    .id(Row.touchGyro)
                }

                if model.touchGyro != 0 {
                    Field {
                        Toggle(L("Раздельно по осям"), isOn: $model.touchGyroSplitAxes)
                            .id(Row.touchGyroSplit)
                            .padFocus(focused(.touchGyroSplit))
                    }

                    if model.touchGyroSplitAxes {
                        Field {
                            SliderRow(title: L("Чувствительность по горизонтали"),
                                      value: $model.touchGyroYawSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.touchGyroYawSens))
                                .id(Row.touchGyroYawSens)
                                .padFocus(focused(.touchGyroYawSens))
                        }

                        Field {
                            SliderRow(title: L("Чувствительность по вертикали"),
                                      value: $model.touchGyroPitchSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.touchGyroPitchSens))
                                .id(Row.touchGyroPitchSens)
                                .padFocus(focused(.touchGyroPitchSens))
                        }
                    } else {
                        Field {
                            SliderRow(title: L("Чувствительность гироскопа"),
                                      value: $model.touchGyroSens,
                                      range: 0.2...3.0, step: 0.1,
                                      readout: String(format: "%.1f", model.touchGyroSens))
                                .id(Row.touchGyroSens)
                                .padFocus(focused(.touchGyroSens))
                        }
                    }

                    // The iPad is held differently from a pad and its sensor is
                    // read down a different path, so which way each axis comes
                    // out is a separate question from the controller's and gets
                    // a separate pair of switches.
                    Field {
                        Toggle(L("Инверсия по горизонтали"), isOn: $model.touchGyroInvertYaw)
                            .id(Row.touchGyroInvertYaw)
                            .padFocus(focused(.touchGyroInvertYaw))
                    }

                    Field {
                        Toggle(L("Инверсия по вертикали"), isOn: $model.touchGyroInvertPitch)
                            .id(Row.touchGyroInvertPitch)
                            .padFocus(focused(.touchGyroInvertPitch))
                    }
                }
            }

            Panel(L("Звук")) {
                Field {
                    SliderRow(title: L("Громкость"),
                              value: $model.volume,
                              range: 0...1, step: 0.05,
                              readout: "\(Int(model.volume * 100))%")
                        .id(Row.volume)
                        .padFocus(focused(.volume))
                }
                Field {
                    SliderRow(title: L("Музыка"),
                              value: $model.musicVolume,
                              range: 0...1, step: 0.05,
                              readout: "\(Int(model.musicVolume * 100))%")
                        .id(Row.music)
                        .padFocus(focused(.music))
                }
            }

            Panel(L("Игра")) {
                Field(note: L("note.pickup")) {
                    ChoiceRow(title: L("Переключаться на подобранное оружие"),
                              selection: $model.autoSwitch,
                              focused: focused(.autoSwitch)) {
                        Text(L("Никогда")).tag(0)
                        Text(L("Только новое")).tag(2)
                        Text(L("Новое или лучше")).tag(4)
                        Text(L("Всегда")).tag(1)
                    }
                    .id(Row.autoSwitch)
                }
                Field {
                    Toggle(L("Подбирать предметы на ходу"), isOn: $model.autoActivate)
                        .id(Row.autoActivate)
                        .padFocus(focused(.autoActivate))
                }
                Field {
                    Toggle(L("Менять оружие, когда кончились патроны"), isOn: $model.emptySwitch)
                        .id(Row.emptySwitch)
                        .padFocus(focused(.emptySwitch))
                }
                Field {
                    Toggle(L("Покачивание камеры при ходьбе"), isOn: $model.viewBob)
                        .id(Row.viewBob)
                        .padFocus(focused(.viewBob))
                }
                Field {
                    SliderRow(title: L("Размер прицела"),
                              value: $model.crosshairSize,
                              range: 16...96, step: 4,
                              readout: "\(Int(model.crosshairSize))")
                        .id(Row.crosshair)
                        .padFocus(focused(.crosshair))
                }
            }

            Panel(L("Диагностика")) {
                Field {
                    Toggle(L("Панель производительности"), isOn: $model.perfHud)
                        .id(Row.perfHud)
                        .padFocus(focused(.perfHud))
                }
                Field {
                    Toggle(L("Запись производительности в perf.csv"), isOn: $model.perfLog)
                        .id(Row.perfLog)
                        .padFocus(focused(.perfLog))
                }
                Field(note: L("note.diag")) {
                    Toggle(L("Запись событий контроллера в лог"), isOn: $model.padLog)
                        .id(Row.padLog)
                        .padFocus(focused(.padLog))
                }
            }
        }
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let rows = self.rows
        switch key {
        case .up, .down:
            guard !rows.isEmpty else { return }
            let next = cursor + (key == .down ? 1 : -1)
            // Down past the last row hands the cursor to the footer, rather
            // than sitting against the end of the list with nowhere to go.
            guard next < rows.count else { onFooter(); return }
            cursor = max(next, 0)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor], anchor: .center)
            }
        case .left, .right, .confirm:
            guard rows.indices.contains(cursor) else { return }
            let row = rows[cursor]
            act(row, key)
            // Switching the gyro on inserts its settings under this row.
            // Follow the row that was just changed rather than the index, so
            // the cursor does not slide onto a control that appeared beneath it.
            if let moved = self.rows.firstIndex(of: row) { cursor = moved }
        default:
            break
        }
    }

    private func kind(of row: Row) -> Kind {
        switch row {
        case .moveDigital:   return .flag(\.moveDigital)
        case .yaw:           return .range(\.lookYawSpeed, 60...400, 10)
        case .pitch:         return .range(\.lookPitchSpeed, 40...300, 10)
        case .deadzone:      return .range(\.stickDeadzone, 0.02...0.35, 0.01)
        case .invertLook:    return .flag(\.invertLook)
        case .rumble:        return .range(\.rumble, 0...100, 5)
        case .rumbleImpact:  return .flag(\.rumbleImpact)
        case .rumbleImpactScale: return .range(\.rumbleImpactScale, 0...2, 0.05)
        case .adaptive:      return .flag(\.adaptiveTriggers)
        case .gyroSplit:     return .flag(\.gyroSplitAxes)
        case .gyroSens:      return .range(\.gyroSens, 0.2...3.0, 0.1)
        case .gyroYawSens:   return .range(\.gyroYawSens, 0.2...3.0, 0.1)
        case .gyroPitchSens: return .range(\.gyroPitchSens, 0.2...3.0, 0.1)
        case .gyroInvertYaw:   return .flag(\.gyroInvertYaw)
        case .gyroInvertPitch: return .flag(\.gyroInvertPitch)
        case .gyroYawSource: return .choice(\.gyroYawSource, [0, 1, 2])
        case .gyroMode:      return .choice(\.gyroMode, [0, 1, 2])
        case .touchControls: return .choice(\.touchControls, [0, 1, 2])
        case .touchLookSplit: return .flag(\.touchLookSplitAxes)
        case .touchLookSens: return .range(\.touchLookSens, 0.3...3.0, 0.1)
        case .touchLookYawSens:   return .range(\.touchLookYawSens, 0.3...3.0, 0.1)
        case .touchLookPitchSens: return .range(\.touchLookPitchSens, 0.3...3.0, 0.1)
        case .touchGyro:     return .choice(\.touchGyro, [0, 1, 2])
        case .touchGyroSplit: return .flag(\.touchGyroSplitAxes)
        case .touchGyroSens: return .range(\.touchGyroSens, 0.2...3.0, 0.1)
        case .touchGyroYawSens:   return .range(\.touchGyroYawSens, 0.2...3.0, 0.1)
        case .touchGyroPitchSens: return .range(\.touchGyroPitchSens, 0.2...3.0, 0.1)
        case .touchGyroInvertYaw:   return .flag(\.touchGyroInvertYaw)
        case .touchGyroInvertPitch: return .flag(\.touchGyroInvertPitch)
        case .volume:        return .range(\.volume, 0...1, 0.05)
        case .music:         return .range(\.musicVolume, 0...1, 0.05)
        case .autoSwitch:    return .choice(\.autoSwitch, [0, 2, 4, 1])
        case .autoActivate:  return .flag(\.autoActivate)
        case .emptySwitch:   return .flag(\.emptySwitch)
        case .viewBob:       return .flag(\.viewBob)
        case .crosshair:     return .range(\.crosshairSize, 16...96, 4)
        case .perfHud:       return .flag(\.perfHud)
        case .perfLog:       return .flag(\.perfLog)
        case .padLog:        return .flag(\.padLog)
        case .test:          return .press { showTest = true }
        case .binds:         return .press { showBinds = true }
        case .reset:         return .press { model.applyDefaultBindings() }
        }
    }

    private func act(_ row: Row, _ key: PadKey) {
        switch kind(of: row) {
        case .flag(let path):
            // Cross flips it; left and right set it outright, which is what a
            // switch looks like it should do.
            switch key {
            case .confirm: model[keyPath: path].toggle()
            case .left:    model[keyPath: path] = false
            default:       model[keyPath: path] = true
            }
        case .range(let path, let range, let step):
            guard key != .confirm else { return }
            padStep(&model[keyPath: path], by: step, in: range, up: key != .left)
        case .choice(let path, let options):
            padCycle(&model[keyPath: path], through: options, forward: key != .left)
        case .press(let action):
            if key == .confirm { action() }
        }
    }
}

private struct BindingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PadScope()
    @State private var cursor = 0
    /// Driven by hand rather than by NavigationLink alone, so that Cross can
    /// push the same screen a tap does.
    @State private var path: [PadButton] = []

    private func focused(_ button: PadButton) -> Bool {
        pad.connected && pad.isActive(scope)
            && PadButton.all.indices.contains(cursor) && PadButton.all[cursor].id == button.id
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    ForEach(PadButton.all, id: \.id) { button in
                        NavigationLink(value: button) {
                            HStack {
                                Text(button.title)
                                Spacer()
                                Text(model.binding(for: button).map { L($0.title) } ?? "—")
                                    .foregroundStyle(model.binding(for: button) == nil
                                                     ? Color.secondary : Theme.accent)
                            }
                        }
                        .id(button.id)
                        .padFocus(focused(button))
                    }
                }
                .navigationDestination(for: PadButton.self) { button in
                    ActionPicker(model: model, pad: pad, button: button)
                }
                .navigationTitle(L("Кнопки контроллера"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Готово")) { dismiss() }
                    }
                }
                .onReceive(pad.strokes) { key in handle(key, proxy) }
            }
        }
        .padScope(pad, scope)
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        switch key {
        case .up, .down:
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), PadButton.all.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(PadButton.all[cursor].id, anchor: .center)
            }
        case .confirm:
            guard PadButton.all.indices.contains(cursor) else { return }
            path.append(PadButton.all[cursor])
        case .back:
            dismiss()
        default:
            break
        }
    }
}

private struct ActionPicker: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let button: PadButton
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PadScope()
    @State private var cursor = 0

    /// The rows in the order they are drawn, nil being "unassigned". The list
    /// below walks the same groups in the same order, so an index here always
    /// means the row the player is looking at.
    private var rows: [GameAction?] {
        [nil] + GameAction.groups.flatMap { group in
            GameAction.all.filter { $0.group == group }
        }
    }

    private func focused(_ action: GameAction?) -> Bool {
        guard pad.connected, pad.isActive(scope), rows.indices.contains(cursor) else { return false }
        return rows[cursor]?.id == action?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Button(L("Не назначено"), role: .destructive) {
                        model.assign(nil, to: button)
                        dismiss()
                    }
                    .id("—")
                    .padFocus(focused(nil))
                }
                ForEach(GameAction.groups, id: \.self) { group in
                    Section(L(group)) {
                        ForEach(GameAction.all.filter { $0.group == group }, id: \.id) { action in
                            Button {
                                model.assign(action, to: button)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(L(action.title)).foregroundStyle(Color.primary)
                                    Spacer()
                                    if model.bindings[button.id] == action.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .id(action.id)
                            .padFocus(focused(action))
                        }
                    }
                }
            }
            .navigationTitle(button.title)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
        .padScope(pad, scope)
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let rows = self.rows
        switch key {
        case .up, .down:
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), rows.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor]?.id ?? "—", anchor: .center)
            }
        case .confirm:
            guard rows.indices.contains(cursor) else { return }
            model.assign(rows[cursor], to: button)
            dismiss()
        case .back:
            dismiss()
        default:
            break
        }
    }
}
