import Foundation

func sampleState() -> SavedState {
    let laptop = Monitor(id: "demo-laptop",name: "MacBook Pro",bounds: Frame(x: 0,y: 0,width: 1440,height: 900),visible: Frame(x: 0,y: 25,width: 1440,height: 850),isPrimary: true)
    let display = Monitor(id: "demo-desktop",name: "Portrait Display",bounds: Frame(x: -1600,y: -900,width: 1600,height: 2560),visible: Frame(x: -1600,y: -875,width: 1600,height: 2510))
    let screens = [laptop,display]
    let apps = [("com.apple.Safari","Safari","Documentation",display.id,Frame(x: 0,y: 0,width: 0.5,height: 1)),
                ("com.microsoft.VSCode","Visual Studio Code","WindowMemory — editor",display.id,Frame(x: 0.5,y: 0,width: 0.5,height: 0.7)),
                ("com.apple.Terminal","Terminal","Build & test",display.id,Frame(x: 0.5,y: 0.7,width: 0.5,height: 0.3)),
                ("com.apple.Notes","Notes","Project notes",laptop.id,Frame(x: 0,y: 0,width: 1,height: 1))]
    let windows = apps.map { WindowSlot(bundleID: $0.0,appName: $0.1,title: $0.2,monitorID: $0.3,relative: $0.4) }
    let work = Layout(id: "demo-work",name: "工作",updatedAt: Date(),monitors: screens,windows: windows,launchRules: [LaunchRule(bundleID: "com.microsoft.VSCode",delay: 2,windowTimeout: 45)])
    var meeting = work; meeting.id = "demo-meeting"; meeting.name = "会议"; meeting.windows = Array(windows.prefix(1))
    var focus = work; focus.id = "demo-focus"; focus.name = "专注"; focus.windows = Array(windows.suffix(2))
    return SavedState(layouts: [work,meeting,focus],activeLayouts: [layoutKey(screens): work.id])
}
