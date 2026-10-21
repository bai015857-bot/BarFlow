import Foundation

struct MenuBarLayout {
    var separatorFrame: CGRect
    var anchorFrame: CGRect
    var screenFrame: CGRect
    var separatorScreenID: UInt32
    var anchorScreenID: UInt32

    var allowsCollapse: Bool {
        let frames = [separatorFrame, anchorFrame, screenFrame]
        guard frames.allSatisfy({ frame in
            [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
        }) else { return false }
        return separatorScreenID == anchorScreenID
            && anchorFrame.width >= 12
            && screenFrame.contains(anchorFrame)
            && separatorFrame.maxX <= anchorFrame.minX + 1
            && abs(separatorFrame.midY - anchorFrame.midY) <= 4
    }
}
