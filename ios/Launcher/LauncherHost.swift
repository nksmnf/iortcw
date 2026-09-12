//  LauncherHost.swift -- showing the launcher from C.
//
//  The engine calls IOSLauncher_RunModal() from main(), before Com_Init. At that
//  point SDL's delegate has finished launching (so UIKit is live and the
//  runloop is running) but SDL has not created its window yet, because that
//  happens inside Com_Init -> CL_Init -> GLimp_Init. So there is nothing to
//  conflict with: we put up our own window, spin the runloop until the user
//  presses Play, and hand back.
//
//  The price of running that early is that there are no cvars yet, so the
//  launcher cannot ask the engine what the player chose last time. It asks the
//  stored config instead -- ios_bridge.c reads ios_launcher.cfg back when
//  com_fullyInitialized is false. Anything here that builds a LauncherModel
//  depends on that: without it the model comes up on its defaults and writes
//  them over the player's settings.
//
//  Entry points are @_cdecl so C can call them without a generated -Swift.h,
//  which keeps the build's header ordering simple.

import SwiftUI
import UIKit

@MainActor
final class LauncherHost {
    static let shared = LauncherHost()

    private var window: UIWindow?
    private(set) var model: LauncherModel?

    /// Skip straight into the game, for players who have already set everything
    /// up and do not want a menu every launch. Settable from the launcher, or
    /// with `defaults write <bundle id> IORTCWSkipLauncher -bool YES`.
    ///
    /// Ignored when the game data is missing: there would be nothing to skip
    /// to except a fatal error in FS_Startup.
    var isSkipping: Bool {
        UserDefaults.standard.bool(forKey: "IORTCWSkipLauncher")
            && IOSBridge_HasGameData()
    }

    /// Debug aid: start hosting straight away, with whatever is stored in the
    /// hosting settings. A script driving the simulator cannot tap the button,
    /// and the console screen is the one part of this that only exists once a
    /// server is actually running. Unset in normal use.
    var isAutoHosting: Bool {
        UserDefaults.standard.bool(forKey: "IORTCWAutoHost")
            && IOSBridge_IsMultiplayer()
            && IOSBridge_HasGameData()
    }

    func present() {
        guard window == nil else { return }

        let model = LauncherModel()
        self.model = model

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }

        window.rootViewController = UIHostingController(rootView: LauncherView(model: model))
        // Above SDL's window, for when the launcher is reopened mid-game.
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Set when the player starts a server that has no renderer. The launcher
    /// then stays on screen and becomes the server's console instead of handing
    /// the display to a game that will never draw anything.
    var hostingModel: MultiplayerModel?

    func dismiss() {
        // A dedicated server draws nothing at all, so there is no game window to
        // hand over to: dismissing here would leave a black screen with no way
        // back. Swap the launcher's contents for the console instead and keep
        // the window.
        if let mp = hostingModel {
            window?.rootViewController =
                UIHostingController(rootView: ServerConsoleView(mp: mp))
            model = nil
            return
        }

        let ours = window
        window = nil
        model = nil
        ours?.isHidden = true

        // Key status does not come back on its own. This window was made key to
        // put it in front, and hiding it leaves UIKit to choose a successor --
        // which is not necessarily the game's window, because the touch overlay
        // sits above it and is deliberately never key. Everything that asks
        // "which window is in front" then gets an answer nobody intended,
        // including the system when it decides whether this app is handling the
        // controller itself or whether it should drive the interface with it.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        if let game = scene?.windows.first(where: {
            $0 !== ours && !$0.isHidden && $0.windowLevel == .normal
        }) {
            game.makeKeyAndVisible()
        }
    }
}

/// Put the launcher up and block until Play is pressed.
///
/// Blocking here is safe and is the simplest correct thing: we are on the main
/// thread with the runloop already running, so pumping it keeps UIKit, SwiftUI
/// animations and controller notifications all live while the engine waits.
@_cdecl("IOSLauncher_RunModal")
public func IOSLauncher_RunModal() {
    var skipped = false

    MainActor.assumeIsolated {
        if LauncherHost.shared.isAutoHosting {
            // The launcher still has to be on screen: hosting without a
            // renderer turns it into the server console rather than dismissing
            // it, and that only works if there is a window to turn into one.
            LauncherHost.shared.present()
            LauncherHost.shared.model?.startHosting()
        } else if LauncherHost.shared.isSkipping {
            // Still build the model and commit. Loading it reads the stored
            // config back, so this rewrites the player's own settings rather
            // than a set of defaults -- and it is the only place a player who
            // skips the launcher ever picks up a migration (see
            // LauncherModel.migrate(from:)).
            // Debug aid: which game to skip into. A script driving the
            // simulator cannot press either button, and every test below the
            // launcher needs one of them pressed. Unset in normal use, where
            // skipping means the campaign.
            let game = UserDefaults.standard.integer(forKey: "IORTCWStartGame")
            IOSDispatch_SetGame(Int32(game))

            let model = LauncherModel()
            if game == IORTCW_GAME_MULTIPLAYER {
                model.mp.commitClient()
            }
            model.commit()
            IOSBridge_LauncherFinished()
            skipped = true
        } else {
            LauncherHost.shared.present()
        }
    }

    if skipped {
        return
    }

    while !Sys_IOS_LauncherIsFinished() {
        // 50ms slices: long enough not to burn the CPU, short enough that the
        // UI stays responsive.
        CFRunLoopRunInMode(.defaultMode, 0.05, true)
    }

    MainActor.assumeIsolated {
        LauncherHost.shared.dismiss()
    }
}

/// Reopen the launcher while the game is running (bound to a console command).
@_cdecl("IOSLauncher_Show")
public func IOSLauncher_Show() {
    Sys_IOS_LauncherReset()
    IOSLauncher_RunModal()
}
