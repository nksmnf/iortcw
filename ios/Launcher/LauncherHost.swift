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
    private var model: LauncherModel?

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

    func dismiss() {
        window?.isHidden = true
        window = nil
        model = nil
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
        if LauncherHost.shared.isSkipping {
            // Still build the model and commit. Loading it reads the stored
            // config back, so this rewrites the player's own settings rather
            // than a set of defaults -- and it is the only place a player who
            // skips the launcher ever picks up a migration (see
            // LauncherModel.migrate(from:)).
            let model = LauncherModel()
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
